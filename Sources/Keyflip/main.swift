import AppKit
import LayoutConversion

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore!
    private var tap: EventTap!
    private var pair: Pair!
    private var convert: ConvertController!
    private var status: StatusItemController!
    private var supervisor: TapSupervisor!

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
                wait: MainActorWait()
            )
        )
        // The tap's whole life is the supervisor's: it arms one as soon as the
        // grant lands, without a relaunch, and takes it away the moment the
        // grant goes (ADR 0009).
        supervisor = TapSupervisor(tap: tap)
        supervisor.start()
        convert.start()
        status = StatusItemController(settings: settings, pair: pair, tap: tap)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
