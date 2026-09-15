enum RewriteOutcome: Equatable {
    case applied
    // Unreadable terminal fields have no readback; posted keys remain best effort.
    case posted
    case unknown
    case failed

    var shouldFollow: Bool { self == .applied || self == .posted }
}
