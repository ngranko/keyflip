import AppKit
import ApplicationServices
import Foundation

/// A 500-line ring in memory, mirrored to ~/Library/Logs/Keyflip.log.
///
/// File writes run on a background queue so they cannot stall the event tap.
enum DebugLog {
    static let fileURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("Keyflip.log")
    }()

    private static let store = Store()

    static var onChange: (@Sendable () -> Void)? {
        get { store.onChange }
        set { store.onChange = newValue }
    }

    static func event(_ message: String) {
        let stamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withInternetDateTime, .withFractionalSeconds]
        )
        store.append("\(stamp)  \(message)")
    }

    static func snapshot() -> String {
        store.snapshot()
    }

    static func describeText(_ text: String) -> String {
        "<redacted; \(text.utf16.count) UTF-16 units>"
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private let io = DispatchQueue(label: "local.Keyflip.debuglog", qos: .utility)

        /// Only Keyflip itself mirrors to disk. Every process on this machine
        /// shares the one log, and a test run's lines are shaped exactly like
        /// production events in the file read to diagnose real conversions —
        /// the test host is `swiftpm-testing-helper`, whether it runs from the
        /// bundle or from `swift run`. The in-memory ring still fills, so the
        /// menu's log window still shows everything either way.
        private static let isTheApp = ProcessInfo.processInfo.processName == "Keyflip"

        /// Touched only from `io`, which is serial.
        private lazy var handle: FileHandle? = {
            guard Self.isTheApp else { return nil }
            FileManager.default.createFile(atPath: DebugLog.fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            guard let handle = try? FileHandle(forWritingTo: DebugLog.fileURL),
                  (try? handle.truncate(atOffset: 0)) != nil else { return nil }
            return handle
        }()

        var onChange: (@Sendable () -> Void)? {
            get { lock.withLock { _onChange } }
            set { lock.withLock { _onChange = newValue } }
        }
        private var _onChange: (@Sendable () -> Void)?

        func append(_ line: String) {
            let notify: (@Sendable () -> Void)? = lock.withLock {
                lines.append(line)
                if lines.count > 500 {
                    lines.removeFirst(lines.count - 500)
                }
                return _onChange
            }
            io.async { [self] in
                try? handle?.write(contentsOf: Data((line + "\n").utf8))
            }
            notify?()
        }

        func snapshot() -> String {
            lock.withLock { lines.joined(separator: "\n") }
        }
    }
}

@MainActor
enum DebugLogWindow {
    private static var panel: NSPanel?
    private static var view: NSTextView?
    private static let reveal = Reveal()

    static func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Keyflip debug log"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true
            scroll.borderType = .noBorder
            scroll.translatesAutoresizingMaskIntoConstraints = false

            let text = NSTextView(frame: scroll.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            text.textContainerInset = NSSize(width: 8, height: 8)
            text.minSize = NSSize(width: 0, height: 0)
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            if let container = text.textContainer {
                container.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                container.widthTracksTextView = true
            }
            scroll.documentView = text

            let button = NSButton(title: "Reveal log file", target: reveal, action: #selector(Reveal.reveal))
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false

            panel.contentView?.addSubview(scroll)
            panel.contentView?.addSubview(button)
            if let content = panel.contentView {
                NSLayoutConstraint.activate([
                    button.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
                    button.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
                    scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    scroll.topAnchor.constraint(equalTo: content.topAnchor),
                    scroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -8),
                ])
            }

            self.panel = panel
            self.view = text
            DebugLog.onChange = {
                DispatchQueue.main.async { DebugLogWindow.refresh() }
            }
        }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    private static func refresh() {
        guard let view else { return }
        view.string = DebugLog.snapshot()
        view.scrollToEndOfDocument(nil)
    }

    private final class Reveal: NSObject {
        @objc func reveal() {
            NSWorkspace.shared.activateFileViewerSelecting([DebugLog.fileURL])
        }
    }
}

func axName(_ err: AXError) -> String {
    switch err {
    case .success: return "success"
    case .apiDisabled: return "apiDisabled"
    case .cannotComplete: return "cannotComplete"
    case .noValue: return "noValue"
    case .attributeUnsupported: return "attributeUnsupported"
    case .notImplemented: return "notImplemented"
    case .invalidUIElement: return "invalidUIElement"
    case .failure: return "failure"
    default: return "ax(\(err.rawValue))"
    }
}
