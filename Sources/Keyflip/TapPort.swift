import CoreGraphics
import Foundation

/// The tap's mach port, and the thread that answers it.
///
/// A tap that can delete events and stops answering swallows everything in its
/// mask: the machine loses the keyboard and every mouse click while the pointer
/// still moves. Three rules keep that from lasting. The port is answered on a
/// thread of its own, so a stall on the main thread — where every AX call may
/// block for a second — can never hold a keystroke. It is created able to
/// delete only while something actually needs deleting. And a timeout is taken
/// at its word: the tap held someone's event, so it goes, and a fresh one has
/// to earn its place back.
final class TapPort: @unchecked Sendable {
    private let mask: CGEventMask
    private let answer: (CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    private let lock = NSLock()
    private var port: CFMachPort?
    private var options: CGEventTapOptions?
    private var thread: Thread?
    private var loop: CFRunLoop?
    private var health = TapHealth()
    private var retired = false

    init(mask: CGEventMask, answer: @escaping (CGEventType, CGEvent) -> Unmanaged<CGEvent>?) {
        self.mask = mask
        self.answer = answer
    }

    var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return port != nil
    }

    /// Given up on after repeated timeouts, and not to be rebuilt unattended.
    var isRetired: Bool {
        lock.lock()
        defer { lock.unlock() }
        return retired
    }

    /// What the live tap may do to an event. Nil while there is no tap.
    var mode: CGEventTapOptions? {
        lock.lock()
        defer { lock.unlock() }
        return options
    }

    /// Idempotent, and refuses while retired: nothing automatic may put a tap
    /// back that had to be taken away to give the user their keyboard.
    @discardableResult
    func start(_ options: CGEventTapOptions) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if port != nil { return true }
        guard !retired else { return false }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: options,
            eventsOfInterest: mask,
            callback: { _, type, event, info in
                guard let info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<TapPort>.fromOpaque(info).takeUnretainedValue().answer(type, event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        port = created
        self.options = options
        serve(created)
        CGEvent.tapEnable(tap: created, enable: true)
        return true
    }

    /// Leaves nothing behind that could still be handed an event: an
    /// invalidated port is inert whatever state this process is in.
    func stop() {
        lock.lock()
        let port = self.port
        let loop = self.loop
        self.port = nil
        self.options = nil
        self.loop = nil
        thread?.cancel()
        thread = nil
        lock.unlock()

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let loop { CFRunLoopStop(loop) }
    }

    /// A person granting Accessibility again is reason enough to try a retired
    /// tap once more, with a clean record.
    func rearm() {
        lock.lock()
        defer { lock.unlock() }
        retired = false
        health.forget()
    }

    /// What to do with a `tapDisabledBy…` event.
    ///
    /// A timeout means an event sat waiting on this process, so the tap goes —
    /// putting it back in place is what turned a revoked grant into half a
    /// minute of dead keyboard. Rebuilding is the supervisor's job, and a tap
    /// the window server refuses to create is the one honest answer about this
    /// process's grant there is: `AXIsProcessTrusted` went on saying yes
    /// throughout (ADR 0009).
    func recoverFromDisable(_ type: CGEventType) {
        guard type == .tapDisabledByTimeout else {
            lock.lock()
            let port = self.port
            lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return
        }
        giveUp("tap timed out")
    }

    /// Take the tap away over evidence it held someone's input. A second strike
    /// inside the minute is a pattern rather than a hiccup, and retires it.
    func giveUp(_ reason: String) {
        lock.lock()
        let healthy = health.survivesTimeout(at: ProcessInfo.processInfo.systemUptime)
        retired = !healthy
        lock.unlock()

        DebugLog.event(
            healthy
                ? "\(reason) → tap torn down; a fresh one must prove the grant"
                : "\(reason) → tap left off so input keeps flowing"
        )
        stop()
    }

    /// The port is answered here and nowhere else, so nothing the app does on
    /// the main thread can delay an event on its way to the front app.
    private func serve(_ port: CFMachPort) {
        // Handed to exactly one thread, which is the only place it is ever
        // touched.
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let thread = Thread { [weak self] in
            let loop: CFRunLoop = CFRunLoopGetCurrent()
            self?.adopt(loop)
            CFRunLoopAddSource(loop, source, .commonModes)
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 60, false)
            }
        }
        thread.name = "local.Keyflip.eventtap"
        thread.qualityOfService = QualityOfService.userInteractive
        self.thread = thread
        thread.start()
    }

    /// A thread that was already stopped must not put its dead run loop back.
    private func adopt(_ loop: CFRunLoop) {
        lock.lock()
        defer { lock.unlock() }
        guard thread === Thread.current else { return }
        self.loop = loop
    }
}
