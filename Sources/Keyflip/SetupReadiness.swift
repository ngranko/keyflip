enum SetupReadiness: Equatable {
    case needsPermission, needsPair, needsTap, ready

    init(trusted: Bool, pairReady: Bool, tapActive: Bool) {
        if !trusted { self = .needsPermission }
        else if !pairReady { self = .needsPair }
        else if !tapActive { self = .needsTap }
        else { self = .ready }
    }

    var message: String {
        switch self {
        case .needsPermission: return "Enable Accessibility to let Keyflip read and replace text in the focused field."
        case .needsPair: return "Choose two different supported keyboard layouts. Add missing layouts in System Settings → Keyboard → Text Input."
        case .needsTap: return "Keyboard monitoring is inactive. Retry, or check Keyflip’s Accessibility permission in System Settings."
        case .ready: return "Ready. Try a conversion below, then click Done."
        }
    }
}
