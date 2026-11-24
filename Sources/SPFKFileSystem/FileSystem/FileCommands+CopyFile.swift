// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-filesystem

#if os(macOS)

    import Darwin
    import Foundation
    import SPFKBase

    extension FileCommands {
        /// One file through `copyfile(3)`, with its metadata, refusing an existing destination.
        /// The calling task's cancellation stops a byte copy within the file; a clone is instant.
        nonisolated static func copyFile(_ source: URL, to destination: URL, cloning: Bool, meter: CopyMeter) throws {
            let state = copyfile_state_alloc()
            defer { copyfile_state_free(state) }

            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(copyCallback, to: UnsafeRawPointer.self))
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(meter).toOpaque())

            var flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_EXCL)
            if cloning { flags |= copyfile_flags_t(COPYFILE_CLONE) }

            meter.beginFile()

            guard copyfile(source.path, destination.path, state, flags) != 0 else { return }

            let code = errno

            if code == ECANCELED, meter.wasCancelled { throw CancellationError() }

            throw posixError(code, url: destination)
        }

        /// Reports data progress and quits once the task is cancelled. Any error stage quits too:
        /// continuing there retries the failed write, and quitting keeps the error's `errno`.
        private nonisolated static let copyCallback: copyfile_callback_t = { what, stage, state, _, _, context in
            guard stage != COPYFILE_ERR else { return COPYFILE_QUIT }
            guard what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS, let context else { return COPYFILE_CONTINUE }

            let meter = Unmanaged<CopyMeter>.fromOpaque(context).takeUnretainedValue()
            var copied: off_t = 0
            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
            meter.fileProgress(Int64(copied))

            guard Task.isCancelled else { return COPYFILE_CONTINUE }

            meter.wasCancelled = true
            return COPYFILE_QUIT
        }
    }

    /// A copy run's bytes, reported about 200 times across the run and at its end. Used only on
    /// the thread running the copy.
    final class CopyMeter {
        let total: Int64
        private let step: Int64
        private let report: (@Sendable (Int64, Int64) -> Void)?

        /// The bytes of the files already copied.
        private var finished: Int64 = 0
        private var reported: Int64 = 0

        /// The data copy of the current file stopped on the task's cancellation.
        var wasCancelled = false

        init(total: Int64, report: (@Sendable (Int64, Int64) -> Void)?) {
            self.total = total
            self.report = report
            step = max(total / 200, 1)
        }

        func beginFile() {
            wasCancelled = false
        }

        func fileProgress(_ copied: Int64) {
            send(finished + copied)
        }

        func fileFinished(_ size: Int64) {
            finished += size
            send(finished)
        }

        func finish() {
            if reported != finished { report?(finished, total) }
        }

        private func send(_ bytes: Int64) {
            guard bytes - reported >= step else { return }
            reported = bytes
            report?(bytes, total)
        }
    }

#endif
