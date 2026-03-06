// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation

public actor DirectoryObserver {
    static let stabilizationChecks: Int = 1
    static let pollInterval: TimeInterval = 0.25

    public weak var delegate: DirectoryObserverDelegate?

    public func setDelegate(_ delegate: DirectoryObserverDelegate?) {
        self.delegate = delegate
    }

    public nonisolated let url: URL

    private let eventMask: DispatchSource.FileSystemEvent

    private var pollTask: Task<Void, Error>?
    private var isWatching: Bool { source != nil }

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isPolling = false
    private var previousContents: Set<URL>?

    public init(url: URL, eventMask: DispatchSource.FileSystemEvent = .all) throws {
        guard url.isDirectory else {
            throw NSError(description: "URL must be a directory")
        }

        self.url = url
        self.eventMask = eventMask

        let initialContents = Self.contentsOfDirectory(at: url)
        self.previousContents = initialContents
    }

    deinit {
        source?.cancel()
        source = nil
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
    }

    public func start() throws {
        guard !isWatching else { return }

        // descriptor requested for event notifications only
        let descriptor = open(url.path, O_EVTONLY)

        guard descriptor != -1 else {
            throw NSError(description: "failed to open url: \(url.path)")
        }

        fileDescriptor = descriptor

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: eventMask,
            queue: .global(qos: .background)
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            Task { await self.directoryDidChange() }
        }

        source?.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        source?.resume()
    }

    public func stop() {
        guard isWatching else { return }

        pollTask?.cancel()
        pollTask = nil

        source?.cancel()
        source = nil
        fileDescriptor = -1
    }
}

// MARK: - Private methods

extension DirectoryObserver {
    private func directoryDidChange() {
        guard !isPolling else { return }

        Log.debug("* change detected for \(url.path)")

        isPolling = true
        startPolling()
    }

    private static func contentsOfDirectory(at url: URL) -> Set<URL> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )) ?? []

        return Set(urls)
    }

    /// Returns a snapshot of directory metadata for change comparison.
    /// Uses filename → file size mapping to detect when writes have settled.
    private nonisolated func directoryMetadata(url: URL) -> [String: Int] {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return [:]
        }

        var metadata = [String: Int]()

        for filename in contents {
            let fileUrl = url.appendingPathComponent(filename)

            guard let fileSize = fileUrl.fileSize else {
                continue
            }

            metadata[filename] = fileSize
        }

        return metadata
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            var stableCount = 0

            while !Task.isCancelled {
                let snapshot = directoryMetadata(url: url)

                try await Task.sleep(seconds: Self.pollInterval)
                try Task.checkCancellation()

                let current = directoryMetadata(url: url)
                let changed = current != snapshot

                if changed {
                    stableCount = 0
                } else {
                    stableCount += 1
                }

                if stableCount >= Self.stabilizationChecks {
                    await postNotification()
                    break
                }
            }

            await resetPollingState()
        }
    }

    private func resetPollingState() {
        isPolling = false
    }

    private func postNotification() async {
        guard let previousContents else { return }

        let newContents = Self.contentsOfDirectory(at: url)

        let newElements = newContents.subtracting(previousContents)
        let deletedElements = previousContents.subtracting(newContents)

        self.previousContents = newContents

        if !deletedElements.isEmpty {
            await delegate?.handleObservation(event:
                .removed(files: deletedElements, source: url)
            )
        }

        if !newElements.isEmpty {
            await delegate?.handleObservation(event:
                .new(files: newElements, source: url)
            )
        }
    }
}

extension DirectoryObserver: Equatable {
    public static func == (lhs: DirectoryObserver, rhs: DirectoryObserver) -> Bool {
        lhs.url == rhs.url
    }
}

extension DirectoryObserver: Hashable {
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

extension DirectoryObserver: CustomStringConvertible {
    nonisolated public var description: String {
        "DirectoryObserver(url: \"\(url.path)\")"
    }
}
