# Bounded rewrites and native settings

This supersedes the permanent refusal cache and assume-applied policy in ADR 0007, and the custom menu controls in ADR 0005.

A rewrite reports one of four outcomes. `applied` means readback confirmed it. `posted` means Keyflip posted synthesized events to an unreadable field but exposes no readable value. `unknown` means the result cannot be established. `failed` means the operation failed or lost ownership of the field. Only applied and posted outcomes follow the destination layout. Unknown outcomes discard the mirror and do not retry blindly.

Confirmed Accessibility writes update the typing mirror. A last-word target includes whitespace between the word and the caret, preserving both spacing and caret placement. Keystroke confirmation checks the expected complete value when the original value is readable. A dropped insertion gets at most one repair, and that repair needs its own confirmation.

Two refusals suppress Accessibility writes for the same field for ten minutes. The cache holds at most 128 fields, clears on launch, and expires entries so an updated or recovered editor can be tried again. The old app-name preference is removed.

Accessibility operations share a 300 ms messaging budget, with at most 100 ms per message. Field reads are limited to 65,536 UTF-16 units. A reported character count over that limit prevents a full-value request; if the app omits its count, an oversized returned value is rejected. Synthesized replacements allow at most 4,096 UTF-16 units and 4,096 deletions. Unicode chunks preserve surrogate pairs and use linear traversal. These limits intentionally skip very large conversions.

Tap creation, replacement, and retirement are serialized. Each callback belongs to one generation and retains its context until its run-loop source is removed. A callback that cannot enter immediately passes input through and clears the typing session. Chords fire once per key press. Modifier-clicks cancel double-taps, and recording ends on a click or panel deactivation. An inactive tap can be retried from the menu.

Settings use standard menu items and layout submenus for keyboard navigation and Accessibility support. Conversion supports base and Shift characters only; the picker and README state the limits on Option characters, dead keys, and IMEs.

The disk log rotates at 1 MiB during a launch and starts empty on the next launch. It never includes field contents. Release jobs reuse a tag only when it points at the current commit and can resume an interrupted upload. Workflow actions are pinned to commits; only the publishing job has repository write permission. Pull requests run tests and a release build without signing credentials.

Stateful editor tests separate event posting from delivery. They cover mirror synchronization, whitespace, duplicate insertion, delayed repair, and overlapping triggers. Real applications still need smoke testing because Accessibility behavior varies by editor.
