// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import CoreServices
    import Foundation

    /// Delegate protocol for receiving file modification events from ``FileModificationObserver``.
    public protocol FileModificationObserverDelegate: AnyObject, Sendable {
        /// Called when one or more tracked files have been externally modified.
        /// - Parameter urls: The set of file URLs whose modification dates changed.
        func fileModificationObserver(didDetectModifications urls: Set<URL>) async
    }

    /// Monitors a set of known file URLs for external modifications by watching their parent
    /// directories via a single `FSEventStream`.
    ///
    /// Unlike ``FSEventsDirectoryObserver`` which monitors a single root recursively and detects
    /// file additions/removals via snapshot diffing, `FileModificationObserver` monitors **multiple
    /// unrelated directories** and detects **modifications** to specific known files by comparing
    /// modification dates.
    ///
    /// ## How It Works
    ///
    /// 1. On initialization, tracked file URLs are grouped by parent directory.
    /// 2. On `start()`, a single `FSEventStream` is created monitoring all parent directories.
    /// 3. When the stream fires, the observer checks modification dates of tracked files in
    ///    the affected directories.
    /// 4. Modified files are coalesced over a configurable interval before delivery.
    ///
    /// ## Feedback Loop Prevention
    ///
    /// Uses `kFSEventStreamCreateFlagIgnoreSelf` to ignore changes made by the current process.
    /// Additionally provides `suppress()`/`unsuppress()` for explicit suppression during
    /// app-initiated save operations.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let observer = FileModificationObserver(
    ///     trackedFiles: playlist.trackedFileModificationDates,
    ///     delegate: self
    /// )
    /// await observer.start()
    /// // ... events delivered via delegate.fileModificationObserver(didDetectModifications:) ...
    /// await observer.stop()
    /// ```
    public actor FileModificationObserver {
        /// The delegate receiving modification events.
        public weak var delegate: FileModificationObserverDelegate?

        /// The FSEvents coalescing latency in seconds.
        private let latency: CFTimeInterval

        private var stream: FSEventStreamRef?
        private var callbackContext: CallbackContext?

        /// Maps directory URL → set of tracked file URLs in that directory.
        private var directoryIndex: [URL: Set<URL>]

        /// Maps file URL → last known modification date.
        private var modificationDates: [URL: Date]

        /// Coalescing state.
        private var pendingModifications: Set<URL> = []
        private var coalescingTask: Task<Void, Error>?
        private let coalescingInterval: TimeInterval

        /// When true, incoming FSEvents are ignored.
        private var isSuppressed: Bool = false

        /// Creates a new file modification observer.
        /// - Parameters:
        ///   - trackedFiles: A mapping of file URLs to their last-known modification dates.
        ///   - delegate: The delegate to receive modification events.
        ///   - latency: The FSEvents stream latency in seconds. Default is 0.3.
        ///   - coalescingInterval: How long to coalesce modifications before delivery. Default is 0.5.
        public init(
            trackedFiles: [URL: Date],
            delegate: FileModificationObserverDelegate,
            latency: CFTimeInterval = 0.3,
            coalescingInterval: TimeInterval = 0.5
        ) {
            self.delegate = delegate
            self.latency = latency
            self.coalescingInterval = coalescingInterval
            self.modificationDates = trackedFiles
            self.directoryIndex = Self.buildDirectoryIndex(from: trackedFiles)
        }

        /// Starts observing the parent directories of tracked files for changes.
        ///
        /// Creates an `FSEventStream` monitoring all unique parent directories. Uses
        /// `kFSEventStreamCreateFlagIgnoreSelf` to avoid reacting to changes made by
        /// the current process.
        ///
        /// Idempotent — calling `start()` while already observing is a no-op.
        public func start() {
            guard stream == nil else { return }
            guard directoryIndex.isNotEmpty else { return }

            let context = CallbackContext(self)
            self.callbackContext = context

            var fsContext = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(context).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let pathsToWatch = directoryIndex.keys.map { $0.path as CFString } as CFArray

            guard let newStream = FSEventStreamCreate(
                nil,
                Self.fsEventCallback,
                &fsContext,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                UInt32(
                    kFSEventStreamCreateFlagFileEvents |
                        kFSEventStreamCreateFlagUseCFTypes |
                        kFSEventStreamCreateFlagNoDefer |
                        kFSEventStreamCreateFlagIgnoreSelf
                )
            ) else {
                Log.error("Failed to create FSEventStream for FileModificationObserver")
                return
            }

            stream = newStream

            FSEventStreamSetDispatchQueue(newStream, .main)
            FSEventStreamStart(newStream)

            Log.debug("FileModificationObserver started monitoring \(directoryIndex.count) directories")
        }

        /// Stops observing and releases the `FSEventStream`.
        ///
        /// Cancels any pending coalescing task and clears pending modifications. Safe to call
        /// multiple times.
        public func stop() {
            guard let stream else { return }

            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)

            self.stream = nil
            self.callbackContext = nil

            coalescingTask?.cancel()
            coalescingTask = nil
            pendingModifications.removeAll()

            Log.debug("FileModificationObserver stopped")
        }

        /// Suppresses event processing. Call before the app writes to tracked files.
        public func suppress() {
            isSuppressed = true
        }

        /// Resumes event processing after suppression.
        public func unsuppress() {
            isSuppressed = false
        }

        /// Updates the set of tracked files. Restarts the stream if the set of monitored
        /// directories changes.
        /// - Parameter newFiles: The new mapping of file URLs to modification dates.
        public func updateTrackedFiles(_ newFiles: [URL: Date]) {
            let oldDirs = Set(directoryIndex.keys)
            modificationDates = newFiles
            directoryIndex = Self.buildDirectoryIndex(from: newFiles)
            let newDirs = Set(directoryIndex.keys)

            if oldDirs != newDirs {
                stop()
                start()
            }
        }
    }

    // MARK: - Directory Index

    extension FileModificationObserver {
        /// Groups file URLs by their parent directory.
        static func buildDirectoryIndex(from trackedFiles: [URL: Date]) -> [URL: Set<URL>] {
            var index = [URL: Set<URL>]()

            for url in trackedFiles.keys {
                let dir = url.deletingLastPathComponent()
                index[dir, default: []].insert(url)
            }

            return index
        }
    }

    // MARK: - FSEvents Callback

    extension FileModificationObserver {
        /// Context object bridging the C callback to the Swift actor.
        private final class CallbackContext: @unchecked Sendable {
            weak var observer: FileModificationObserver?

            init(_ observer: FileModificationObserver) {
                self.observer = observer
            }
        }

        /// The C function pointer callback for FSEventStream.
        private static let fsEventCallback: FSEventStreamCallback = {
            _, info, numEvents, eventPaths, eventFlags, _ in

            guard let info else { return }

            let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
            guard let observer = context.observer else { return }

            // Extract paths from the CFArray
            guard let pathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }

            // Extract flags into an array for safe transfer
            let flags = (0 ..< numEvents).map { eventFlags[$0] }

            Task {
                await observer.handleFSEvents(paths: pathArray, flags: flags)
            }
        }
    }

    // MARK: - Event Handling

    extension FileModificationObserver {
        private func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
            guard !isSuppressed else { return }

            // Determine which monitored directories are affected
            var affectedDirs = Set<URL>()

            for path in paths {
                let url = URL(fileURLWithPath: path)

                // The path could be either a file within a monitored directory
                // or the directory itself
                let parentDir = url.deletingLastPathComponent()
                let fileDir = url

                if directoryIndex[parentDir] != nil {
                    affectedDirs.insert(parentDir)
                }

                if directoryIndex[fileDir] != nil {
                    affectedDirs.insert(fileDir)
                }
            }

            guard affectedDirs.isNotEmpty else { return }

            // Check tracked files in affected directories for modification
            var foundModifications = false

            for dir in affectedDirs {
                guard let trackedFiles = directoryIndex[dir] else { continue }

                for fileURL in trackedFiles {
                    guard let cachedDate = modificationDates[fileURL],
                          let currentDate = fileURL.modificationDate,
                          currentDate != cachedDate
                    else {
                        continue
                    }

                    // Update cached date and record the modification
                    modificationDates[fileURL] = currentDate
                    pendingModifications.insert(fileURL)
                    foundModifications = true
                }
            }

            if foundModifications {
                scheduleFlush()
            }
        }

        private func scheduleFlush() {
            coalescingTask?.cancel()
            coalescingTask = Task { [weak self] in
                try await Task.sleep(seconds: self?.coalescingInterval ?? 0.5)
                try Task.checkCancellation()

                guard let self else { return }

                let urls = await self.flushPending()

                guard !urls.isEmpty else { return }

                await self.delegate?.fileModificationObserver(didDetectModifications: urls)
            }
        }

        private func flushPending() -> Set<URL> {
            let urls = pendingModifications
            pendingModifications.removeAll()
            return urls
        }
    }

    // MARK: - CustomStringConvertible

    extension FileModificationObserver: CustomStringConvertible {
        nonisolated public var description: String {
            "FileModificationObserver"
        }
    }
#endif
