public enum SessionResetReason: String, Sendable {
    case explicit
    case appActivated
    case tapStarted
    case tapStopped
    case tapDisabled
    case tapRetired
    case tapBusy
    case menuOpened
    case accessibilityUnavailable
    case secureInput
    case markedText
    case mouseDown
    case shortcut
    case modifiedDeletion
    case caretMovement
    case commitOrCancel
    case forwardDelete
    case backspaceExhausted
    case emptyKeyText
    case nonTextKey
    case mirrorDiscarded
    case mirrorMismatch
}

// Diagnostics carry no characters or key codes that could reconstruct typing.
public struct SessionReset: Sendable {
    public let reason: SessionResetReason
    public let wasLive: Bool
    public let mirroredUTF16: Int
    public let revision: UInt64
}
