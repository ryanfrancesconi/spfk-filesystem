// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import AppKit
    import Foundation
    import SPFKBase

    public protocol VolumeObserverDelegate: AnyObject, Sendable {
        func volumeObserver(didMount volumeURL: URL) async
        func volumeObserver(didUnmount volumeURL: URL) async
    }

    /// Observes volume mount and unmount events via NSWorkspace notifications.
    ///
    /// Must be created and used on the main actor since NSWorkspace requires it.
    ///
    /// ## Usage
    /// ```swift
    /// let observer = VolumeObserver(delegate: self)
    /// observer.start()
    /// // ... events delivered via delegate methods ...
    /// observer.stop()
    /// ```
    @MainActor
    public final class VolumeObserver {
        public weak var delegate: VolumeObserverDelegate?

        private var mountToken: NSObjectProtocol?
        private var unmountToken: NSObjectProtocol?
        private var eventTask: Task<Void, Never>?

        public init(delegate: VolumeObserverDelegate) {
            self.delegate = delegate
        }

        /// Begins observing volume mount and unmount events. Idempotent.
        public func start() {
            guard mountToken == nil else { return }

            let nc = NSWorkspace.shared.notificationCenter

            mountToken = nc.addObserver(
                forName: NSWorkspace.didMountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.eventTask?.cancel()
                    self.eventTask = Task(priority: .utility) { [weak self] in
                        await self?.delegate?.volumeObserver(didMount: volumeURL)
                    }
                }
            }

            unmountToken = nc.addObserver(
                forName: NSWorkspace.didUnmountNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.eventTask?.cancel()
                    self.eventTask = Task(priority: .background) { [weak self] in
                        await self?.delegate?.volumeObserver(didUnmount: volumeURL)
                    }
                }
            }

            Log.debug("VolumeObserver started")
        }

        /// Stops observing, cancels any in-flight event task, and releases notification tokens. Safe to call multiple times.
        public func stop() {
            eventTask?.cancel()
            eventTask = nil
            let nc = NSWorkspace.shared.notificationCenter
            if let token = mountToken { nc.removeObserver(token) }
            if let token = unmountToken { nc.removeObserver(token) }
            mountToken = nil
            unmountToken = nil
            Log.debug("VolumeObserver stopped")
        }
    }
#endif
