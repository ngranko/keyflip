import ApplicationServices
import Foundation
import Testing
@testable import Keyflip

@Test func declineWrapperAndStaticTextRoles() {
    for role in ["AXGroup", "AXWebArea", "AXStaticText", "AXWindow", "?"] {
        #expect(!FieldAccess.supportsTextInput(role: role))
    }
    for role in ["AXTextField", "AXTextArea", "AXComboBox"] {
        #expect(FieldAccess.supportsTextInput(role: role))
    }
}

@Test func distinguishFieldHandlesInsteadOfAppNames() {
    let first = FieldHandle.ax(AXUIElementCreateApplication(1))
    let same = FieldHandle.ax(AXUIElementCreateApplication(1))
    let other = FieldHandle.ax(AXUIElementCreateApplication(2))
    #expect(first.matches(same))
    #expect(!first.matches(other))
    #expect(!FieldHandle.none.matches(.none))
}

@Test func requireExactCaretPositionBeforeDeletion() {
    #expect(FieldAccess.confirmCaret(NSRange(location: 4, length: 0), at: 8,
                                    in: "wordword", expecting: "word") == .wrongPosition)
    #expect(FieldAccess.confirmCaret(NSRange(location: 4, length: 4), at: 8,
                                    in: "wordword", expecting: "word") == .selectionHeld)
}

@Test func requireMatchingTextBehindTheRestoredCaret() {
    #expect(FieldAccess.confirmCaret(NSRange(location: 8, length: 0), at: 8,
                                    in: "wordelse", expecting: "word") == .textChanged)
    #expect(FieldAccess.confirmCaret(NSRange(location: 8, length: 0), at: 8,
                                    in: "", expecting: "word") == .textChanged)
    #expect(FieldAccess.confirmCaret(NSRange(location: 8, length: 0), at: 8,
                                    in: "wordword", expecting: "word") == .collapsed)
}

@Test func verifyCaretTextUsingUTF16Offsets() {
    let value = "🙂 привет "
    #expect(FieldAccess.confirmCaret(NSRange(location: value.utf16.count, length: 0),
                                    at: value.utf16.count, in: value,
                                    expecting: "привет ") == .collapsed)
}

@Test func redactSensitiveContentFromDiagnostics() {
    let secret = "private-token-\(UUID().uuidString)\nmessage"
    let description = DebugLog.describeText(secret)
    DebugLog.event("field value=\(description)")
    #expect(!description.contains(secret))
    #expect(!DebugLog.snapshot().contains(secret))
    #expect(description.contains(String(secret.utf16.count)))
}
