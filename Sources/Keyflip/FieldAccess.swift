import ApplicationServices
import Carbon
import Foundation

struct FieldSnapshot {
    var element: AXUIElement
    /// Only for the log — which app a field belongs to is the first thing you
    /// want when someone reports "it does not work here".
    var app: String
    var role: String
    var value: String
    var selectedRange: NSRange
    var selectedText: String
}

/// What a trigger found under the caret. The cases carry the follow policy
/// (ADR 0004): `field` converts, `noFocus` toggles, the rest are silent.
enum FieldRead {
    case field(FieldSnapshot)
    case noFocus
    case markedText
    case secure
    case unavailable
}

enum FieldAccess {
    /// AX calls block on the target app's run loop. One second is already an
    /// eternity to hold a keystroke, so cap every element we touch.
    private static let timeout: Float = 1

    static func read() -> FieldRead {
        if IsSecureEventInputEnabled() {
            return .secure
        }
        switch focusedElement() {
        case .failed(let read):
            return read
        case .element(let focused):
            let element = bestTextElement(focused)
            AXUIElementSetMessagingTimeout(element, timeout)
            if isSecure(element) {
                return .secure
            }
            if hasMarkedText(element) {
                return .markedText
            }
            let contents = textContents(element)
            let role = string(element, kAXRoleAttribute as CFString) ?? "?"
            return .field(FieldSnapshot(
                element: element,
                app: focusedAppName(),
                role: role,
                value: contents.value,
                selectedRange: contents.range,
                selectedText: contents.selected
            ))
        }
    }

    static func replace(_ snapshot: FieldSnapshot, range: NSRange, with newText: String) -> Bool {
        AXUIElementSetMessagingTimeout(snapshot.element, timeout)
        let valueLength = (snapshot.value as NSString).length
        let canClamp = valueLength > 0
        let nsRange = canClamp ? clamp(range, in: snapshot.value) : range

        // Browser fields often have AXSelectedText and no AXValue. Do not
        // clamp the write away against an empty value.
        if !snapshot.selectedText.isEmpty || nsRange.length > 0 {
            if canClamp, selectedRange(snapshot.element) != nsRange {
                _ = setRange(snapshot.element, nsRange)
            }
            if set(snapshot.element, kAXSelectedTextAttribute as CFString, newText as CFString) {
                if canClamp {
                    _ = setRange(snapshot.element, caret(after: nsRange, newText))
                }
                return true
            }
            DebugLog.event("ax set AXSelectedText failed")
        }

        guard canClamp else {
            DebugLog.event("ax replace abort: empty AXValue, AXSelectedText failed")
            return false
        }
        let updated = (snapshot.value as NSString).replacingCharacters(in: nsRange, with: newText)
        guard set(snapshot.element, kAXValueAttribute as CFString, updated as CFString) else {
            DebugLog.event("ax set AXValue failed")
            return false
        }
        _ = setRange(snapshot.element, caret(after: nsRange, newText))
        return true
    }

    /// Whether a write that *reported* success actually landed.
    ///
    /// Monaco (Cursor, VS Code) answers `AXUIElementSetAttributeValue` with
    /// `.success` and changes nothing, so the return value cannot be trusted.
    /// Deliberately three-way: only a field still holding the original text is
    /// proof of failure. Anything else stays `unknown`, because retyping over a
    /// write that did land would double the text.
    enum WriteCheck {
        case applied
        case unchanged
        case unknown
    }

    static func verify(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        wrote newText: String,
        over original: String
    ) -> WriteCheck {
        let value = textContents(snapshot.element).value as NSString
        guard value.length > 0 else { return .unknown }
        if slice(value, at: range.location, length: (newText as NSString).length) == newText {
            return .applied
        }
        if slice(value, at: range.location, length: (original as NSString).length) == original {
            return .unchanged
        }
        DebugLog.event("ax verify: unexpected \(DebugLog.quote(value as String))")
        return .unknown
    }

    /// Put the target under an AX selection and confirm the field agrees.
    ///
    /// Apps that discard `AXSelectedText` writes often still honour a selection
    /// change — Monaco does — which turns "retype it" into "type over the
    /// selection": no backspace counting and no caret assumptions. Reading the
    /// selection back is the whole point; without it we would be typing over
    /// a range the field never actually took.
    static func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool {
        // The user's own selection is usually already exactly the target — and
        // in apps that ignore programmatic selection (Slack) it is the only
        // selection we will ever get, so check before trying to set one.
        if string(snapshot.element, kAXSelectedTextAttribute as CFString) == text {
            return true
        }
        guard setRange(snapshot.element, range) else { return false }
        return string(snapshot.element, kAXSelectedTextAttribute as CFString) == text
    }

    /// Put the caret back where the snapshot found it and confirm it took.
    ///
    /// A refused write can still leave the range it selected behind. The
    /// keystroke fallback deletes by count, so one backspace against a stale
    /// selection would eat the whole run and the next N would eat what came
    /// before it. Returns false when the caret cannot be proven collapsed.
    static func restoreCaret(_ snapshot: FieldSnapshot) -> Bool {
        let caret = NSRange(location: snapshot.selectedRange.upperBound, length: 0)
        _ = setRange(snapshot.element, caret)
        guard let now = selectedRange(snapshot.element) else { return false }
        return now.length == 0
    }

    private static func slice(_ value: NSString, at location: Int, length: Int) -> String? {
        guard location >= 0, length >= 0, location + length <= value.length else { return nil }
        return value.substring(with: NSRange(location: location, length: length))
    }

    private static func caret(after range: NSRange, _ newText: String) -> NSRange {
        NSRange(location: range.location + (newText as NSString).length, length: 0)
    }

    private static func focusedAppName() -> String {
        let system = AXUIElementCreateSystemWide()
        guard let app = copy(system, kAXFocusedApplicationAttribute as CFString) else { return "?" }
        return string(app as! AXUIElement, kAXTitleAttribute as CFString) ?? "?"
    }

    private enum FocusResult {
        case element(AXUIElement)
        case failed(FieldRead)
    }

    private static func focusedElement() -> FocusResult {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)

        var focused: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        if err == .success, let focused {
            return .element(focused as! AXUIElement)
        }
        if err == .apiDisabled {
            return .failed(.unavailable)
        }
        DebugLog.event("ax focusedUIElement \(axName(err))")

        // Some apps only answer through their own application element.
        var app: AnyObject?
        let appErr = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &app
        )
        if appErr == .apiDisabled {
            return .failed(.unavailable)
        }
        guard appErr == .success, let app else {
            return .failed(.noFocus)
        }
        let appElement = app as! AXUIElement
        AXUIElementSetMessagingTimeout(appElement, timeout)
        var inner: AnyObject?
        let innerErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &inner
        )
        guard innerErr == .success, let inner else {
            return .failed(.noFocus)
        }
        return .element(inner as! AXUIElement)
    }

    /// AXValue is often empty in web/Electron fields while
    /// AXNumberOfCharacters + AXStringForRange still work.
    private static func textContents(
        _ element: AXUIElement
    ) -> (value: String, range: NSRange, selected: String) {
        var value = string(element, kAXValueAttribute as CFString) ?? ""
        if (value as NSString).length == 0,
           let chars = intValue(element, kAXNumberOfCharactersAttribute as CFString), chars > 0
        {
            value = stringForRange(element, NSRange(location: 0, length: chars)) ?? ""
        }
        let range = selectedRange(element)
            ?? NSRange(location: (value as NSString).length, length: 0)
        return (value, range, selectedString(element, range: range, value: value))
    }

    /// The focused element is sometimes a wrapper whose text lives one or two
    /// levels down (web areas, Electron). Fall back to the longest descendant.
    private static func bestTextElement(_ root: AXUIElement) -> AXUIElement {
        var best = root
        var bestLen = textContents(root).value.utf16.count
        guard bestLen == 0 else { return root }

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth > 0,
                  let children = copy(element, kAXChildrenAttribute as CFString) as? [AXUIElement]
            else { return }
            for child in children.prefix(24) {
                let len = textContents(child).value.utf16.count
                if len > bestLen {
                    best = child
                    bestLen = len
                }
                walk(child, depth: depth - 1)
            }
        }
        walk(root, depth: 3)
        return best
    }

    private static func intValue(_ element: AXUIElement, _ attr: CFString) -> Int? {
        (copy(element, attr) as? NSNumber)?.intValue
    }

    private static func selectedString(_ element: AXUIElement, range: NSRange, value: String) -> String {
        if let selected = string(element, kAXSelectedTextAttribute as CFString), !selected.isEmpty {
            return selected
        }
        if range.length > 0, let slice = stringForRange(element, range), !slice.isEmpty {
            return slice
        }
        let clamped = clamp(range, in: value)
        guard clamped.length > 0 else { return "" }
        return (value as NSString).substring(with: clamped)
    }

    private static func stringForRange(_ element: AXUIElement, _ range: NSRange) -> String? {
        var cf = CFRange(location: range.location, length: range.length)
        guard let ax = AXValueCreate(.cfRange, &cf) else { return nil }
        var value: AnyObject?
        let err = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            ax,
            &value
        )
        guard err == .success else { return nil }
        return value as? String
    }

    /// Presence of a marker-range attribute is not composition. Web and AppKit
    /// views expose that attribute while idle; treating it as marked text made
    /// every convert a no-op.
    private static func hasMarkedText(_ element: AXUIElement) -> Bool {
        guard let marked = string(element, "AXMarkedText" as CFString) else { return false }
        return !marked.isEmpty
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute as CFString) == (kAXSecureTextFieldSubrole as String)
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw = copy(element, kAXSelectedTextRangeAttribute as CFString) else { return nil }
        var range = CFRange()
        guard CFGetTypeID(raw) == AXValueGetTypeID(),
              AXValueGetValue(raw as! AXValue, .cfRange, &range)
        else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private static func setRange(_ element: AXUIElement, _ range: NSRange) -> Bool {
        var cf = CFRange(location: range.location, length: range.length)
        guard let ax = AXValueCreate(.cfRange, &cf) else { return false }
        return set(element, kAXSelectedTextRangeAttribute as CFString, ax)
    }

    /// A range the field will accept: inside the text, never inverted.
    static func clamp(_ range: NSRange, in text: String) -> NSRange {
        let len = (text as NSString).length
        let loc = max(0, min(range.location, len))
        let end = max(loc, min(range.location + range.length, len))
        return NSRange(location: loc, length: end - loc)
    }

    private static func copy(_ element: AXUIElement, _ attr: CFString) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attr, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attr: CFString) -> String? {
        copy(element, attr) as? String
    }

    private static func set(_ element: AXUIElement, _ attr: CFString, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attr, value) == .success
    }
}
