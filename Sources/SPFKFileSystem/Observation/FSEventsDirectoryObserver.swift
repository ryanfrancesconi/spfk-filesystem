// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import CoreServices
    import Foundation

    /// macOS-only directory observer using the FSEvents API for efficient recursive monitoring.
    ///
    /// Unlike `DirectoryObserver` which creates one kqueue file descriptor per directory,
    /// `FSEventsDirectoryObserver` uses a single `FSEventStream` to monitor an entire directory
    /// tree recursively. This is more efficient for large directory hierarchies and automatically
    /// handles subdirectory creation and deletion.
    ///
    /// Produces the same `DirectoryEvent` values as the existing observation system.
    public actor FSEventsDirectoryObserver {
        public nonisolated let url: URL

        public weak var delegate: DirectoryEnumerationObserverDelegate?

        private let latency: CFTimeInterval

        private var stream: FSEventStreamRef?
        private var callbackContext: CallbackContext?
        private var previousSnapshot: Set<URL>
        private var eventQueue: Set<DirectoryEvent> = []
        private var coalescingTask: Task<Void, Error>?

        /// Creates a new FSEvents-based directory observer.
        /// - Parameters:
        ///   - url: The directory URL to observe recursively.
        ///   - delegate: The delegate to receive directory change events.
        ///   - latency: The coalescing latency for FSEvents in seconds. Default is 0.3.
        public init(
            url: URL,
            delegate: DirectoryEnumerationObserverDelegate,
            latency: CFTimeInterval = 0.3
        ) throws {
            guard url.isDirectory else {
                throw NSError(description: "URL must be a directory")
            }

            self.url = url
            self.delegate = delegate
            self.latency = latency
            self.previousSnapshot = Self.recursiveContents(of: url)
        }

        /// Starts observing the directory for file system changes.
        public func start() {
            guard stream == nil else { return }

            let context = CallbackContext(self)
            self.callbackContext = context

            var fsContext = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(context).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            let pathsToWatch = [url.path as CFString] as CFArray

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
                        kFSEventStreamCreateFlagNoDefer
                )
            ) else {
                Log.error("Failed to create FSEventStream for \(url.path)")
                return
            }

            stream = newStream

            FSEventStreamSetDispatchQueue(newStream, .main)
            FSEventStreamStart(newStream)

            Log.debug("FSEventsDirectoryObserver started for \(url.path)")
        }

        /// Stops observing the directory.
        public func stop() {
            guard let stream else { return }

            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)

            self.stream = nil
            self.callbackContext = nil

            coalescingTask?.cancel()
            coalescingTask = nil
            eventQueue.removeAll()

            Log.debug("FSEventsDirectoryObserver stopped for \(url.path)")
        }
    }

    // MARK: - FSEvents Callback

    extension FSEventsDirectoryObserver {
        /// Context object bridging the C callback to the Swift actor.
        private final class CallbackContext: @unchecked Sendable {
            weak var observer: FSEventsDirectoryObserver?

            init(_ observer: FSEventsDirectoryObserver) {
                self.observer = observer
            }
        }

        /// The C function pointer callback for FSEventStream.
        private static let fsEventCallback: FSEventStreamCallback = {
            _, info, numEvents, eventPaths, eventFlags, _ in

            guard let info else { return }

            let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
            guard let observer = context.observer else { return }

            // Extract flags into an array for safe transfer
            let flags = (0 ..< numEvents).map { eventFlags[$0] }

            // Extract paths from the CFArray
            guard let pathArray = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }

            Task {
                await observer.handleFSEvents(paths: pathArray, flags: flags)
            }
        }
    }

    // MARK: - Event Handling

    extension FSEventsDirectoryObserver {
        private func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
            // Take a fresh snapshot and diff against previous
            let newSnapshot = Self.recursiveContents(of: url)
            let added = newSnapshot.subtracting(previousSnapshot)
            let removed = previousSnapshot.subtracting(newSnapshot)
            previousSnapshot = newSnapshot

            if !removed.isEmpty {
                eventQueue.insert(.removed(files: removed, source: url))
            }

            if !added.isEmpty {
                eventQueue.insert(.new(files: added, source: url))
            }

            if !added.isEmpty || !removed.isEmpty {
                scheduleFlush()
            }
        }

        private func scheduleFlush() {
            coalescingTask?.cancel()
            coalescingTask = Task { [weak self] in
                try await Task.sleep(seconds: 0.05)
                try Task.checkCancellation()

                guard let self else { return }

                let events = await self.flushQueue()

                guard !events.isEmpty else { return }

                try await self.delegate?.directoryUpdated(events: events)
            }
        }

        private func flushQueue() -> Set<DirectoryEvent> {
            let events = eventQueue
            eventQueue.removeAll()
            return events
        }

        /// Returns all file URLs recursively within the given directory, skipping hidden files.
        nonisolated static func recursiveContents(of url: URL) -> Set<URL> {
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var results = Set<URL>()

            for case let fileURL as URL in enumerator {
                results.insert(fileURL)
            }

            return results
        }
    }

    // MARK: - CustomStringConvertible

    extension FSEventsDirectoryObserver: CustomStringConvertible {
        nonisolated public var description: String {
            "FSEventsDirectoryObserver(url: \"\(url.path)\")"
        }
    }
#endif
