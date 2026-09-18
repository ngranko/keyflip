import Foundation

@MainActor
extension FieldRewriter {
    func settleCaret(
        in snapshot: FieldSnapshot,
        after range: NSRange,
        text: String,
        attempt: Int = 0,
        then done: @escaping (RewriteOutcome) -> Void
    ) {
        guard canContinue() else { done(.failed); return }
        var destination = snapshot
        destination.reading.selectedRange = NSRange(location: range.location + text.utf16.count, length: 0)
        // Apps can reset the selection when an asynchronous text write lands.
        let result = writer.restoreCaret(destination, expecting: text)
        guard result != .collapsed else { done(.applied); return }
        guard result != .textChanged, attempt < Self.confirmAttempts else {
            DebugLog.event("rewrite caret unconfirmed: \(result)")
            done(.unknown)
            return
        }
        holdTrigger(for: Self.confirmInterval) { [weak self] in
            self?.settleCaret(in: snapshot, after: range, text: text, attempt: attempt + 1, then: done)
        }
    }
}
