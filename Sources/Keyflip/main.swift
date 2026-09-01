import AppKit
import LayoutConversion

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var tap: EventTap!
    private var pair: Pair!
    private var convert: ConvertController!
    private var status: StatusItemController!
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore()
        tap = EventTap(trigger: settings.trigger, interval: NSEvent.doubleClickInterval)
        let reader = AXFieldReader()
        pair = Pair(settings: settings, catalog: SystemLayouts())
        convert = ConvertController(
            settings: settings,
            tap: tap,
            pair: pair,
            reader: reader,
            rewriter: FieldRewriter(
                settings: settings,
                session: tap.session,
                reader: reader,
                writer: AXFieldWriter(),
                wait: MainQueueWait()
            )
        )
        convert.start()
        status = StatusItemController(settings: settings, pair: pair, tap: tap)

        guard !tap.isActive else { return }
        // The tap only fails for one reason worth handling: no Accessibility.
        // Nag (ADR 0004), then keep trying so the grant takes effect without a
        // relaunch — TCC lets a running process create the tap once trusted.
        Permissions.promptIfAccessibilityLapsed(available: false)
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
