import Foundation

/// What a field's own readback says about blind keystrokes posted at it.
///
/// The keystroke rungs erase first and type second, so anything the window
/// server does between the two halves can drop one of them. Reading the field
/// back afterwards is the only way to find out which half arrived.
enum KeyLanding {
    /// The field holds the text, or holds too little to argue with.
    case landed
    /// The field kept the erase and nothing else: the words are gone.
    case vanished
    /// The field holds something else — worth a log line, not a second guess
    /// at text we cannot account for.
    case disagrees

    /// `previous` is what the field showed before the rewrite: a field that
    /// never reports its contents — every terminal — reads empty either way,
    /// and must never be read as having lost anything. `mirror` is the typing
    /// session's account of the same field, which survives only while nothing
    /// else has touched the keyboard, and so separates keystrokes that were
    /// dropped from a user who moved on.
    static func judge(
        field value: String,
        wasShowing previous: String,
        expected text: String,
        mirror: String
    ) -> KeyLanding {
        if value.contains(text) { return .landed }
        // Monaco answers with the trailing token rather than the whole field:
        // a readback contained *in* what we wrote is a truncated read.
        if !value.isEmpty, text.contains(value) { return .landed }
        guard value.allSatisfy(\.isWhitespace) else { return .disagrees }
        guard !previous.isEmpty else { return .landed }
        return mirror.contains(text) ? .vanished : .disagrees
    }
}
