// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

import Foundation
import SPFKBase

/// Low-level, single-directory file system observer using kqueue via `DispatchSource`.
///
/// **Available on all Apple platforms** (macOS, iOS, tvOS, watchOS).
///
/// Each `DirectoryObserver` opens one file descriptor (`O_EVTONLY`) on the target directory
/// and creates a `DispatchSourceFileSystemObject` to receive kernel-level change notifications.
/// When a change is detected, it polls the directory contents at ``pollInterval`` intervals
/// until file sizes stabilize (``stabilizationChecks`` consecutive unchanged snapshots),
/// then diffs against the previous contents to produce ``DirectoryEvent`` values.
///
/// This observer monitors only the **immediate children** of a single directory — it is not
/// recursive. For recursive monitoring, use one of the higher-level options:
///
/// - ``DirectoryEnumerationObserver`` (cross-platform): Creates one `DirectoryObserver` per
///   subdirectory via ``ObservationData``. Works on all Apple platforms but uses one file
///   descriptor per directory.
/// - ``FSEventsDirectoryObserver`` (macOS only): Uses a single `FSEventStream` for the entire
///   tree. More efficient for large hierarchies, but requires macOS.
///
/// ## Usage
///
/// ```swift
/// let observer = try DirectoryObserver(url: directoryURL)
/// await observer.setDelegate(myDelegate)
/// try await observer.start()
/// // ... changes are reported via delegate ...
/// await observer.stop()
/// ```
public actor DirectoryObserver {
    /// Number of consecutive stable metadata snapshots required before reporting a change.
    static let stabilizationChecks: Int = 1

    /// Interval between metadata polls while waiting for writes to settle.
    static let pollInterval: TimeInterval = 0.25

    /// The delegate that receives ``DirectoryEvent`` notifications.
    public weak var delegate: DirectoryObserverDelegate?

    /// Sets the delegate for receiving change notifications.
    /// - Parameter delegate: The delegate to receive events, or `nil` to stop receiving.
    public func setDelegate(_ delegate: DirectoryObserverDelegate?) {
        self.delegate = delegate
    }

    /// The directory URL being observed.
    public nonisolated let url: URL

    private let eventMask: DispatchSource.FileSystemEvent

    private var pollTask: Task<Void, Error>?
    private var isWatching: Bool { source != nil }

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var isPolling = false
    private var previousContents: Set<URL>?

    /// Creates a new directory observer.
    /// - Parameters:
    ///   - url: The directory URL to observe. Must be an existing directory.
    ///   - eventMask: The file system events to monitor. Defaults to `.all`.
    /// - Throws: If the URL is not a directory.
    public init(url: URL, eventMask: DispatchSource.FileSystemEvent = .all) throws {
        guard url.isDirectory else {
            throw NSError(description: "URL must be a directory")
        }

        self.url = url
        self.eventMask = eventMask

        let initialContents = Self.contentsOfDirectory(at: url)
        previousContents = initialContents
    }

    deinit {
        source?.cancel()
        source = nil
        if fileDescriptor != -1 {
            close(fileDescriptor)
        }
    }

    /// Begins monitoring the directory for file system changes.
    ///
    /// Opens a file descriptor on the directory and schedules a `DispatchSource` to receive
    /// kernel notifications. Idempotent — calling `start()` while already watching is a no-op.
    ///
    /// - Throws: If the file descriptor cannot be opened (e.g., permissions).
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

    /// Stops monitoring and releases the file descriptor and dispatch source.
    ///
    /// Cancels any in-flight stabilization polling. Safe to call multiple times.
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
    public nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

extension DirectoryObserver: CustomStringConvertible {
    public nonisolated var description: String {
        "DirectoryObserver(url: \"\(url.path)\")"
    }
}
