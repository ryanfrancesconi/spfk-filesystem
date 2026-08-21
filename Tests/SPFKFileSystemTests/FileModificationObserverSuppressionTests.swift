// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import Testing

    /// Suppression nests. Both products wrap a save in `suppress()` / `unsuppress()`, and a save
    /// reached from inside another suppressed region -- or a second entry through a dialog the
    /// save gate does not cover -- would otherwise re-arm the observer while the outer region is
    /// still writing.
    ///
    /// The stream itself cannot be driven from here: it is created with
    /// `kFSEventStreamCreateFlagIgnoreSelf`, so a write by the test process delivers no events.
    /// `isSuppressed` is the exact condition `handleFSEvents` guards on.
    @Suite
    struct FileModificationObserverSuppressionTests {
        private final class Recorder: FileModificationObserverDelegate {
            func fileModificationObserver(didDetectModifications modifications: [URL: FileModificationKind]) async {}
        }

        private func makeObserver() -> FileModificationObserver {
            FileModificationObserver(trackedFiles: [:], delegate: Recorder())
        }

        @Test func nestedSuppressionNeedsAsManyUnsuppressCalls() async {
            let observer = makeObserver()

            await observer.suppress()
            await observer.suppress()

            await observer.unsuppress()
            #expect(await observer.isSuppressed)

            await observer.unsuppress()
            #expect(await observer.isSuppressed == false)
        }

        @Test func unsuppressClampsAtZero() async {
            let observer = makeObserver()

            await observer.unsuppress()
            await observer.unsuppress()

            await observer.suppress()
            #expect(await observer.isSuppressed)

            await observer.unsuppress()
            #expect(await observer.isSuppressed == false)
        }
    }
#endif
