import AppKit
import ApplicationServices
import Foundation

/// A 500-line ring in memory, mirrored to ~/Library/Logs/Keyflip.log.
///
/// `event` is called from the event-tap callback, which runs on the main run
/// loop: anything slow here gets the tap disabled by timeout. So the file write
/// is an append on a background queue, never a rewrite of the whole ring.
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

    static func quote(_ text: String) -> String {
        let ns = text as NSString
        if ns.length > 80 {
            return "\u{201C}\(ns.substring(to: 80))\u{2026}\u{201D} (\(ns.length) chars)"
        }
        return "\u{201C}\(text)\u{201D}"
    }

    private final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        private let io = DispatchQueue(label: "local.Keyflip.debuglog", qos: .utility)

        /// Appended and trimmed rather than truncated at launch: the artifacts
        /// this log explains show up once in a hundred conversions, and the app
        /// is reinstalled between most of them.
        private static let maxBytes = 1 << 20

        /// Touched only from `io`, which is serial.
        private lazy var handle: FileHandle? = {
            let path = DebugLog.fileURL.path
            if FileManager.default.fileExists(atPath: path) {
                Self.trim(path)
            } else {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: DebugLog.fileURL) else { return nil }
            _ = try? handle.seekToEnd()
            return handle
        }()

        /// Keep the tail, cut on a line boundary so the first surviving entry
        /// is still a whole entry.
        private static func trim(_ path: String) {
            guard let data = FileManager.default.contents(atPath: path), data.count > maxBytes else {
                return
            }
            var tail = data.suffix(maxBytes)
            if let newline = tail.firstIndex(of: 0x0A) {
                tail = tail[tail.index(after: newline)...]
            }
            try? Data(tail).write(to: URL(fileURLWithPath: path))
        }

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
