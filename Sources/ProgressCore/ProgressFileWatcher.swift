import CoreServices
import Foundation

/// Watches a directory for file-system changes and fires a coalesced callback.
/// Adapted from OpenClaw's CoalescingFSEventsWatcher.
final class ProgressFileWatcher: @unchecked Sendable {
    private let queue: DispatchQueue
    private var stream: FSEventStreamRef?
    private var pending = false

    private let path: String
    private let onChange: @Sendable () -> Void
    private let coalesceDelay: TimeInterval

    init(
        path: String,
        coalesceDelay: TimeInterval = 0.1,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.path = path
        self.queue = DispatchQueue(label: "engineering.happy.progress.fswatcher")
        self.coalesceDelay = coalesceDelay
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil else { return }

        let retainedSelf = Unmanaged.passRetained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf.toOpaque(),
            retain: nil,
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<ProgressFileWatcher>.fromOpaque(pointer).release()
            },
            copyDescription: nil
        )

        let paths = [path] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags
        ) else {
            retainedSelf.release()
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        if !FSEventStreamStart(stream) {
            self.stream = nil
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

extension ProgressFileWatcher {
    private static let callback: FSEventStreamCallback = { _, info, numEvents, _, _, _ in
        guard let info, numEvents > 0 else { return }
        let watcher = Unmanaged<ProgressFileWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.handleChange()
    }

    private func handleChange() {
        if pending { return }
        pending = true
        queue.asyncAfter(deadline: .now() + coalesceDelay) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.onChange()
        }
    }
}
