# Layout conversion

A personal macOS menu bar app that converts text typed on the wrong input source and follows into the intended one.

## Language

**Input source**:
A keyboard layout enabled in macOS (for example English ABC or Russian).
_Avoid_: Keyboard layout, locale, language, IME (unless it really is an IME)

**Participating source**:
An input source the user has opted into for conversion. A subset of the system's enabled input sources.
_Avoid_: Active layout, enabled layout, selected layout

**Conversion**:
Rewriting characters as if the same physical keys had been typed on a different participating source (`сщьзкурутышму` → `comprehensive`).
_Avoid_: Translation, transliteration, spellcheck, autocorrect

**Pair**:
The two participating sources conversion runs between.
_Avoid_: Layout set, N-way, active layouts

**Trigger**:
The configurable shortcut that runs conversion, including a double-tap of a modifier key.
_Avoid_: Hotkey, gesture, shortcut (when you mean this app's trigger)

**Follow**:
After conversion, selecting the participating source the text was converted into, so the next keystrokes match.
_Avoid_: Layout switch (alone), input source change (alone)

**From-source**:
The participating source the target is treated as having been typed on. Detected from the text, not from the currently selected input source.
_Avoid_: Current layout, source layout (when you mean this)

**Destination**:
The other member of the pair. Conversion rewrites toward it; follow selects it.
_Avoid_: Target layout, output layout

**Vote**:
A character votes for a participating source when it inverts on that source and not the other. From-source is whichever source gets more votes.
_Avoid_: Score, confidence, language detection

**Target**:
The text conversion rewrites: a non-empty selection, or else the last non-whitespace run while a typing session is live.
_Avoid_: Buffer, snippet, last token (when you mean this)

**Typing session**:
A stretch of character typing, including backspace and a trailing space, until a click in the field, a caret-moving key, a focus change, or paste. Last-word conversion is allowed only while this session is live.
_Avoid_: Focus, insertion point, caret position (alone)

**Typing mirror**:
A best-effort copy of what the app received since the typing session began, built from the keystrokes the tap saw. The only witness in terminals and Electron editors, which answer Accessibility with an empty value. Empty whenever it cannot be trusted.
_Avoid_: Buffer, history, echo, typed text (alone)

**Marked text**:
In-flight IME composition (underlined, not yet committed). A trigger during marked text is a no-op.
_Avoid_: Selection, last word

**Field reading**:
What a trigger saw in the focused field — its owning app, role, text, caret and selection — as plain values, with no live Accessibility handle attached. Every decision about the target is made from a reading.
_Avoid_: Snapshot, field state, AX value (when you mean this)

**Field handle**:
The live Accessibility element a reading came from. Only the write path dereferences it; a reading replayed in a test carries none, and writes against it decline.
_Avoid_: Element, AXUIElement (when you mean the app-facing type), reference

**Rung**:
One way of getting a conversion into the field, tried in a fixed order: typing over the user's own selection, an Accessibility write, a selection the app set and typed over, then backspaces counted from the typing mirror. Each assumes more about the app than the one above it.
_Avoid_: Strategy, fallback, attempt, method

**Slot**:
One of the two pickers for the pair (A or B). Each slot is one enabled keyboard layout; the two slots must differ.
_Avoid_: Source A/B (when you mean the picker)
