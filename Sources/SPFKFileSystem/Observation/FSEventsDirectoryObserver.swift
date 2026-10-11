// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import CoreServices
    import Foundation
    import SPFKBase

    /// macOS-only recursive directory observer using the CoreServices FSEvents API.
    ///
    /// **macOS only** (`#if os(macOS)`). Not available on iOS, tvOS, or watchOS.
    ///
    /// Unlike the cross-platform ``DirectoryEnumerationObserver`` which creates one kqueue-based
    /// ``DirectoryObserver`` (file descriptor + `DispatchSource`) per subdirectory,
    /// `FSEventsDirectoryObserver` uses a single `FSEventStream` to monitor an entire directory
    /// tree recursively. This is significantly more efficient for large hierarchies and
    /// automatically handles subdirectory creation and deletion without managing observer lifecycle.
    ///
    /// ## How It Works
    ///
    /// 1. On `start()`, an `FSEventStream` is created with per-file event granularity
    ///    (`kFSEventStreamCreateFlagFileEvents`).
    /// 2. When the stream fires, a full recursive snapshot (`Set<URL>`) is taken and diffed
    ///    against the previous snapshot to produce ``DirectoryEvent/new(files:source:)`` and
    ///    ``DirectoryEvent/removed(files:source:)`` events.
    /// 3. Events are coalesced over a short internal window (0.05s) before delivery to the
    ///    ``DirectoryEnumerationObserverDelegate``.
    ///
    /// ## Platform Comparison
    ///
    /// | | `DirectoryEnumerationObserver` | `FSEventsDirectoryObserver` |
    /// |---|---|---|
    /// | Platform | All Apple platforms | macOS only |
    /// | Underlying API | kqueue (`DispatchSource`) | CoreServices `FSEventStream` |
    /// | Resources | 1 file descriptor per subdirectory | 1 stream total |
    /// | Recursive | Via ``ObservationData`` coordination | Built-in |
    /// | `start()` | `async throws` (opens file descriptors) | Non-throwing |
    /// | Event source URL | Per-subdirectory | Root URL only |
    /// | Stabilization | Polls file sizes until stable | FSEvents `latency` parameter |
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let observer = try FSEventsDirectoryObserver(url: rootURL, delegate: myDelegate)
    /// await observer.start()
    /// // ... events delivered via myDelegate.directoryUpdated(events:) ...
    /// await observer.stop()
    /// ```
    public actor FSEventsDirectoryObserver {
        /// The root directory URL being observed recursively.
        public nonisolated let url: URL

        /// The delegate receiving coalesced ``DirectoryEvent`` batches.
        public weak var delegate: DirectoryEnumerationObserverDelegate?

        /// The FSEvents coalescing latency in seconds.
        private let latency: CFTimeInterval

        /// Written only on the actor; `nonisolated(unsafe)` so `deinit` can tear it down.
        nonisolated(unsafe) private var stream: FSEventStreamRef?
        private var previousSnapshot: Set<URL>
        private var pendingAdded: Set<URL> = []
        private var pendingRemoved: Set<URL> = []
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
            previousSnapshot = Self.recursiveContents(of: url)
        }

        /// An observer released without ``stop()`` would otherwise leave its stream running.
        deinit {
            if let stream { Self.tearDown(stream) }
        }

        /// Starts observing the directory tree for file system changes.
        ///
        /// Creates an `FSEventStream` scheduled on the main dispatch queue with per-file event
        /// granularity. Unlike ``DirectoryObserver/start()``, this method is non-throwing — if
        /// stream creation fails, an error is logged and no events will be delivered.
        ///
        /// Idempotent — calling `start()` while already observing is a no-op.
        public func start() {
            guard stream == nil else { return }

            // Held across the create, which takes the stream's own reference through `retain`.
            let context = Unmanaged.passRetained(CallbackContext(self))
            defer { context.release() }

            var fsContext = FSEventStreamContext(
                version: 0,
                info: context.toOpaque(),
                retain: CallbackContext.retain,
                release: CallbackContext.release,
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

        /// Stops observing and releases the `FSEventStream`.
        ///
        /// Cancels any pending coalescing task and clears the event queue. Safe to call
        /// multiple times.
        public func stop() {
            guard let stream else { return }

            Self.tearDown(stream)
            self.stream = nil

            coalescingTask?.cancel()
            coalescingTask = nil
            pendingAdded.removeAll()
            pendingRemoved.removeAll()

            Log.debug("FSEventsDirectoryObserver stopped for \(url.path)")
        }
    }

    // MARK: - FSEvents Callback

    extension FSEventsDirectoryObserver {
        /// Stops and releases `stream`. Its context is released with it, so an event already in
        /// flight finds no observer rather than freed memory.
        nonisolated static func tearDown(_ stream: FSEventStreamRef) {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }

        /// Context object bridging the C callback to the Swift actor. Owned by the stream.
        private final class CallbackContext: @unchecked Sendable {
            weak var observer: FSEventsDirectoryObserver?

            init(_ observer: FSEventsDirectoryObserver) {
                self.observer = observer
            }

            static let retain: CFAllocatorRetainCallBack = { info in
                guard let info else { return nil }
                _ = Unmanaged<CallbackContext>.fromOpaque(info).retain()
                return info
            }

            static let release: CFAllocatorReleaseCallBack = { info in
                guard let info else { return }
                Unmanaged<CallbackContext>.fromOpaque(info).release()
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

            // Accumulate with cancellation: a URL added then removed (e.g. atomic write
            // temp file) cancels out and is never reported to the delegate.
            pendingAdded.formUnion(added)
            pendingAdded.subtract(removed)

            pendingRemoved.formUnion(removed)
            pendingRemoved.subtract(added)

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

                let events = await flushQueue()

                guard !events.isEmpty else { return }

                try await delegate?.directoryUpdated(events: events)
            }
        }

        private func flushQueue() -> Set<DirectoryEvent> {
            var events = Set<DirectoryEvent>()

            if !pendingAdded.isEmpty {
                events.insert(.new(files: pendingAdded, source: url))
                pendingAdded.removeAll()
            }

            if !pendingRemoved.isEmpty {
                events.insert(.removed(files: pendingRemoved, source: url))
                pendingRemoved.removeAll()
            }

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
        public nonisolated var description: String {
            "FSEventsDirectoryObserver(url: \"\(url.path)\")"
        }
    }
#endif
