import CoreGraphics
import Foundation

final class TapPort: @unchecked Sendable {
    private final class CallbackContext: @unchecked Sendable {
        weak var owner: TapPort?
        let generation = UUID()
        init(owner: TapPort) { self.owner = owner }
    }

    private let observationGap: () -> Void
    private let mask: CGEventMask
    private let answer: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    private let lock = NSRecursiveLock()
    private var port: CFMachPort?
    private var context: CallbackContext?
    private var options: CGEventTapOptions?
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var health = TapHealth()
    private var retired = false

    init(mask: CGEventMask, observationGap: @escaping () -> Void = {}, answer: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
        self.observationGap = observationGap
        self.mask = mask
        self.answer = answer
    }

    var isActive: Bool { locked { port != nil } }
    var isRetired: Bool { locked { retired } }
    var mode: CGEventTapOptions? { locked { options } }

    @discardableResult
    func start(_ options: CGEventTapOptions) -> Bool {
        locked {
            if port != nil { return true }
            guard !retired else { return false }
            return create(options)
        }
    }

    @discardableResult
    func replace(with options: CGEventTapOptions) -> Bool {
        locked {
            guard port != nil else { return false }
            if self.options == options { return true }
            stop()
            return start(options)
        }
    }

    private func create(_ options: CGEventTapOptions) -> Bool {
        let context = CallbackContext(owner: self)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
            eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<CallbackContext>.fromOpaque(info).takeUnretainedValue()
                guard let owner = context.owner else { return Unmanaged.passUnretained(event) }
                return owner.receive(type, event, generation: context.generation)
            }, userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else { return false }
        port = created
        self.context = context
        self.options = options
        serve(created, context: context)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent, generation: UUID) -> Unmanaged<CGEvent>? {
        // Teardown must never make an event wait. A retired callback may only pass through.
        guard lock.try() else {
            observationGap()
            return Unmanaged.passUnretained(event)
        }
        defer { lock.unlock() }
        guard context?.generation == generation else { return Unmanaged.passUnretained(event) }
        return answer(type, event)
    }

    func stop() {
        locked {
            if let port {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
            }
            thread?.cancel()
            if let loop { CFRunLoopStop(loop) }
            port = nil
            context = nil
            options = nil
            loop = nil
            thread = nil
        }
    }

    func rearm() { locked { retired = false; health.forget() } }

    func recoverFromDisable(_ type: CGEventType) {
        locked {
            if type == .tapDisabledByTimeout {
                giveUp("tap timed out")
            } else if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
        }
    }

    func giveUp(_ reason: String) {
        locked {
            guard port != nil else { return }
            retired = !health.survivesTimeout(at: ProcessInfo.processInfo.systemUptime,
                                              mayDeleteEvents: options == .defaultTap)
            DebugLog.event("\(reason) → tap stopped; retired=\(retired)")
            stop()
        }
    }

    private func serve(_ port: CFMachPort, context: CallbackContext) {
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let thread = Thread { [weak self, context] in
            let loop = CFRunLoopGetCurrent()
            self?.locked {
                if self?.context?.generation == context.generation { self?.loop = loop }
            }
            CFRunLoopAddSource(loop, source, .commonModes)
            while !Thread.current.isCancelled { CFRunLoopRunInMode(.defaultMode, 60, false) }
            CFRunLoopRemoveSource(loop, source, .commonModes)
            // The callback's unretained pointer stays valid until its run-loop source is gone.
            withExtendedLifetime(context) {}
        }
        thread.name = "local.Keyflip.eventtap"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
