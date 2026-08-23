import AppKit
import LayoutConversion

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var tap: EventTap!
    private var convert: ConvertController!
    private var status: StatusItemController!
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        tap = EventTap(trigger: settings.trigger, interval: NSEvent.doubleClickInterval)
        convert = ConvertController(settings: settings, tap: tap)
        convert.start()
        status = StatusItemController(settings: settings, convert: convert, tap: tap)

        guard !tap.isActive else { return }
        // The tap only fails for one reason worth handling: no Accessibility.
        // Nag (ADR 0004), then keep trying so the grant takes effect without a
        // relaunch — TCC lets a running process create the tap once trusted.
        Permissions.promptOnceThisLaunch()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.tap.start() else { return }
                self.retryTimer?.invalidate()
                self.retryTimer = nil
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
