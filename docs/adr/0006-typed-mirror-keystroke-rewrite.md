# Mirror what was typed, and retype it where Accessibility cannot reach

ADR 0004 said the rewrite stays AX-only. That holds wherever Accessibility exposes text — but terminals and Electron editors (Cursor, VS Code) draw their own text and answer `AXValue` with an empty string. There is no target to find, so the trigger degraded to a bare layout toggle: the failure the user actually reported.

The tap already sees every keystroke, so the app **mirrors what was typed** (`TypingSession.typed`, fed by `CGEvent.keyboardGetUnicodeString`, so layout and dead keys are already applied) and rewrites by synthesizing **backspaces plus the converted text**. The mirror follows the same lifetime as the typing session and the same last-run-of-non-whitespace rule as the field path, so eligibility does not change — only where the characters come from.

Accessibility stays first: it is exact, it handles selections, and it cannot drift. Synthesized events carry a marker in `eventSourceUserData` so the tap ignores its own output, and are built from a private event source with cleared flags — inheriting a held Option would turn every backspace into delete-word.

Cursor forced a second lesson: it answers `AXUIElementSetAttributeValue` with `.success` and changes nothing, so the return value cannot be trusted and every write is verified by re-reading the field. It does honour `setRange`, though. So the fallbacks are ordered by how much they assume — write, then **select the target and type over the selection**, then backspace over what the mirror claims is there. Only the last one counts characters, and it runs only from a caret proven collapsed: a refused write can leave its selection behind, where one backspace would eat the whole run and the next N would eat what came before it.

The cost is that the last fallback is blind: it trusts the mirror to describe the screen. Where keys do not insert text — vim normal mode is the sharp case — the mirror drifts and the backspaces land somewhere unintended. Selections in those apps stay unreachable, since nothing reports them. Both are accepted; the alternative is the app not working in a terminal at all.

## Amendment: a selection the user made is typed over, not written through

"Accessibility stays first" was too broad, and Cursor spent four attempts proving it. Ordering the fallbacks by how much they assume was right; putting the Accessibility write at the front of that order for *every* target was not.

A selection is the case where the write buys nothing. The field already holds the range — the user put it there — and typing replaces it. Nothing has to be mutated through Accessibility at all, so there is nothing for the app to discard.

And discarding it is not free. Where Monaco refuses the `AXSelectedText` write it also fragments the element's accessibility tree: re-reading the field afterwards returns `relevant`, then `deem not `, the two halves of the run as separate elements, and never a selection. `bestTextElement` picks whichever fragment is longest, so the keystroke fallback has nothing to work from and the trigger is lost. The document is untouched throughout — the next trigger reads it whole — but within the trigger there is no way back. Waiting does not help, because there is no single element that recovers; polling for a second and a half only proved that. The first trigger in a refusing app failed every time, and the ones after it succeeded for one reason: `noteRefusal` had run and the write no longer happened.

So for a selection target the order is now: type over the selection, and fall back to the Accessibility write only if the field will not confirm a selection to type over. Last-word targets are unchanged — there is no selection to type over, setting one is exactly what the keystroke path would have to do anyway, and the typing mirror is there to back the write up.

The cost is that a very long selection is now retyped rather than written in one call, which is slower and sends more synthesized events than a single Accessibility write would. That is the same cost the keystroke path has always carried in Slack and in terminals, and it is worth paying to stop losing the first conversion in every app that refuses.
