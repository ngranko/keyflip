import ApplicationServices
import Carbon
import Foundation
import LayoutConversion

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
                handle: .ax(element),
                reading: FieldReading(
                    app: focusedAppName(),
                    role: role,
                    value: contents.value,
                    selectedRange: contents.range,
                    selectedText: contents.selected
                )
            ))
        }
    }

    /// Three outcomes, not two: a refusal is the app saying no and is worth
    /// remembering against it, while a decline is us not making a write that
    /// reached past the target. Recording a decline in `axWriteRefused`, which
    /// is persisted, would send every later conversion there down the blind
    /// path.
    enum WriteAttempt: Equatable {
        case wrote
        case refused
        case declined
    }

    static func replace(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        with newText: String
    ) -> WriteAttempt {
        guard let element = snapshot.handle.element else { return .declined }
        let reading = snapshot.reading
        AXUIElementSetMessagingTimeout(element, timeout)
        // Browser fields often have AXSelectedText and no AXValue. Nothing
        // that follows may clamp the write away against an empty value.
        let hasValue = (reading.value as NSString).length > 0
        let nsRange = hasValue ? TextRange.clamp(range, in: reading.value) : range

        if !reading.selectedText.isEmpty || nsRange.length > 0,
           writeOverSelection(element, range: nsRange, hasValue: hasValue, with: newText)
        {
            return .wrote
        }
        return writeWholeValue(element, reading, range: nsRange, hasValue: hasValue, with: newText)
    }

    /// Put the target under a selection and write through `AXSelectedText`.
    ///
    /// Written against a selection the field never took, it *inserts* rather
    /// than replaces, leaving the original next to the conversion — Google
    /// Forms collapses a programmatic range and doubles the text that way. So
    /// the range has to read back before the write is allowed to run.
    private static func writeOverSelection(
        _ element: AXUIElement,
        range: NSRange,
        hasValue: Bool,
        with newText: String
    ) -> Bool {
        if hasValue, selectedRange(element) != range {
            guard setRange(element, range), selectedRange(element) == range else {
                DebugLog.event("ax setRange did not take → AXValue")
                return false
            }
        }
        guard set(element, kAXSelectedTextAttribute as CFString, newText as CFString) else {
            DebugLog.event("ax set AXSelectedText failed")
            return false
        }
        if hasValue {
            _ = setRange(element, caret(after: range, newText))
        }
        return true
    }

    /// Replace every character in the field, not just the target.
    ///
    /// Zen's multi-line AXTextArea reports offsets that run behind its own
    /// AXValue, so the string rebuilt here is not always what the field holds
    /// and setting it flattens the difference across the whole document, line
    /// breaks first — a 460-character message spoiled to fix one word. Hence
    /// the refusal to write past the target: anything wider belongs to the
    /// keystroke path, which touches only what it selects.
    private static func writeWholeValue(
        _ element: AXUIElement,
        _ reading: FieldReading,
        range: NSRange,
        hasValue: Bool,
        with newText: String
    ) -> WriteAttempt {
        guard hasValue else {
            DebugLog.event("ax replace abort: empty AXValue, AXSelectedText failed")
            return .refused
        }
        let value = reading.value as NSString
        guard TextRange.spansEverything(range, in: reading.value) else {
            DebugLog.event(
                "ax value write declined: \(value.length - range.length) chars outside " +
                "range=\(range) → retype"
            )
            return .declined
        }
        let updated = value.replacingCharacters(in: range, with: newText)
        guard set(element, kAXValueAttribute as CFString, updated as CFString) else {
            DebugLog.event("ax set AXValue failed")
            return .refused
        }
        _ = setRange(element, caret(after: range, newText))
        return .wrote
    }

    /// Whether a write that *reported* success actually landed — Monaco
    /// answers `.success` and changes nothing.
    ///
    /// Four-way, because "did not read back as expected" hides two opposites:
    /// a field that will not read back at all is safe to assume applied, while
    /// one reading back as neither text has taken something with the write.
    enum WriteCheck: Equatable {
        case applied
        case unchanged
        case unreadable
        case mangled(String)
    }

    static func verify(
        _ snapshot: FieldSnapshot,
        range: NSRange,
        wrote newText: String,
        over original: String
    ) -> WriteCheck {
        guard let element = snapshot.handle.element else { return .unreadable }
        let value = textContents(element).value as NSString
        guard value.length > 0 else { return .unreadable }
        let before = snapshot.reading.value as NSString
        let wrote = (newText as NSString).length
        if slice(value, at: range.location, length: wrote) == newText {
            // The output being there does not prove the original left: an
            // inserting write leaves both and the slice matches either way,
            // which is how a field holding “Никит” *and* “Ybrbn” was logged as
            // a confirmed replace. Length is what tells them apart, so skip the
            // check only for the browser case with no readable value.
            guard before.length > 0 else { return .applied }
            let expected = before.length - range.length + wrote
            return value.length == expected ? .applied : .mangled(value as String)
        }
        if slice(value, at: range.location, length: (original as NSString).length) == original {
            return .unchanged
        }
        return .mangled(value as String)
    }

    /// Put the target under an AX selection and confirm the field agrees.
    ///
    /// Apps that discard `AXSelectedText` writes often still honour a selection
    /// change — Monaco does. Reading the selection back is the whole point:
    /// without it we would type over a range the field never took.
    static func select(_ snapshot: FieldSnapshot, range: NSRange, expecting text: String) -> Bool {
        guard let element = snapshot.handle.element else { return false }
        // The user's own selection is usually already exactly the target — and
        // in apps that ignore programmatic selection (Slack) it is the only
        // selection we will ever get, so check before trying to set one.
        if string(element, kAXSelectedTextAttribute as CFString) == text {
            return true
        }
        // A write the app refused can leave its selection in a state where the
        // first setRange is swallowed — Cursor takes the second. Retry once:
        // the readback is what makes this safe, and it is cheap.
        for _ in 0..<2 {
            guard setRange(element, range) else { continue }
            if string(element, kAXSelectedTextAttribute as CFString) == text {
                return true
            }
        }
        return false
    }

    /// Put the caret back where the snapshot found it, false when it cannot be
    /// proven collapsed. A refused write can leave its selection behind, and
    /// one backspace against that eats the whole run.
    static func restoreCaret(_ snapshot: FieldSnapshot) -> Bool {
        guard let element = snapshot.handle.element else { return false }
        let caret = NSRange(location: snapshot.reading.selectedRange.upperBound, length: 0)
        _ = setRange(element, caret)
        guard let now = selectedRange(element) else { return false }
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
        guard textContents(root).value.isEmpty else { return root }
        var best = root
        var bestLen = 0

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
        let clamped = TextRange.clamp(range, in: value)
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

    /// Web and AppKit views expose the marker attribute while idle, so its
    /// presence is not composition — treating it as such no-op'd every convert.
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
