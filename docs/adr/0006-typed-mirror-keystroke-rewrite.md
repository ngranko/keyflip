# Mirror what was typed, and retype it where Accessibility cannot reach

ADR 0004 said the rewrite stays AX-only. That holds wherever Accessibility exposes text — but terminals and Electron editors (Cursor, VS Code) draw their own text and answer `AXValue` with an empty string. There is no target to find, so the trigger degraded to a bare layout toggle: the failure the user actually reported.

The tap already sees every keystroke, so the app **mirrors what was typed** (`TypingSession.typed`, fed by `CGEvent.keyboardGetUnicodeString`, so layout and dead keys are already applied) and rewrites by synthesizing **backspaces plus the converted text**. The mirror follows the same lifetime as the typing session and the same last-run-of-non-whitespace rule as the field path, so eligibility does not change — only where the characters come from.

Accessibility stays first: it is exact, it handles selections, and it cannot drift. Synthesized events carry a marker in `eventSourceUserData` so the tap ignores its own output, and are built from a private event source with cleared flags — inheriting a held Option would turn every backspace into delete-word.

Cursor forced a second lesson: it answers `AXUIElementSetAttributeValue` with `.success` and changes nothing, so the return value cannot be trusted and every write is verified by re-reading the field. It does honour `setRange`, though. So the fallbacks are ordered by how much they assume — write, then **select the target and type over the selection**, then backspace over what the mirror claims is there. Only the last one counts characters, and it runs only from a caret proven collapsed: a refused write can leave its selection behind, where one backspace would eat the whole run and the next N would eat what came before it.

The cost is that the last fallback is blind: it trusts the mirror to describe the screen. Where keys do not insert text — vim normal mode is the sharp case — the mirror drifts and the backspaces land somewhere unintended. Selections in those apps stay unreachable, since nothing reports them. Both are accepted; the alternative is the app not working in a terminal at all.
