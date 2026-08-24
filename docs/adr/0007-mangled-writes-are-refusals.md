# A write that mangles the field is a refusal, not an unknown

ADR 0006 made every Accessibility write verify itself by re-reading the field, and split the answer three ways: the text we wrote (applied), the text that was there before (refused), or anything else (unknown). Unknown assumed the write had landed, on the reasoning that doubling the text is worse than not converting it.

That reasoning holds for one of the two things unknown was covering. A field that will not read back at all — an empty `AXValue` in a terminal or an Electron editor — tells us nothing, and retyping over a write that did land would double the run. But a field that reads back as *neither* the original nor the output is not silent, it is damaged: the write went in and took the run with it.

Cursor does exactly this to a multi-word selection. Forty-seven characters of Russian went in, forty-three came out deleted, and `щтдн` was left sitting in the editor while the app reported success and Keyflip followed to US. The user undid it, tried again, and got the same result — because unknown never marked the app as refusing, so the next trigger took the same destructive path.

So the check is four-way now. `unreadable` keeps the old assume-applied policy. `mangled` carries what the field actually holds, and the app goes on the retype list so the next trigger uses the selection-plus-keystrokes path that works in Monaco. Both non-final verdicts get the same handful of rechecks first, since an app part-way through applying a write reads back as neither text for a frame or two.

What `mangled` must **not** do is conclude the text is damaged. The first version of this decision did, and gave up — no retype, no follow — on the reasoning that the mirror is dead on a selection and retyping would append a second copy to whatever survived. That was wrong, and the log said so within a day: converting a selection in Cursor failed on the first trigger and succeeded on the second, every time. Monaco's `AXValue` truncates to the trailing token under exactly these conditions, so `deem not relevant` reads back as `relevant` and a field still holding the right text looks wrecked. Giving up cost a good conversion on every occurrence.

So `mangled` hands the target to the keystroke path, like `unchanged` does. That path is safe under either reading of the evidence without having to know which one is true: `select` types over the target only once the field confirms the original is still there and still selected, and backs out when it cannot. Damage and a truncated read are distinguished by the field itself, at the moment it matters, instead of guessed at from a value that cannot be trusted.

The cost is that an app which legitimately reformats what we wrote — trimming it, or re-indenting it — reads as mangled and gets demoted to the keystroke path for the rest of the launch. That path works, so the demotion is cheap, and no app seen so far does it.

## Presence at the target is not proof of replacement

The first version of this check asked only whether the output was sitting at the range we wrote to. It never asked whether the original had left. Those come apart whenever a write inserts instead of replacing: the field ends up holding the conversion *and* the text it was supposed to replace, and the slice at the target location matches regardless. Google Forms in Zen produced exactly that — `Ybrbn` converted to `Никит`, both left in the field, logged as `replace confirmed`. The check that existed to catch leftover text was reporting success on it.

The field's length is what separates them. A replacement changes it by exactly `len(new) - len(range)`; an insertion does not. So a slice that matches at the target location is confirmed only when the length agrees, and a mismatch is `mangled` like any other. The check is skipped where there was no readable `AXValue` to measure against, which is the browser case the write path already treats specially.

The write side had the matching hole. `replace` set the selection and ignored whether it took, and `AXUIElementSetAttributeValue` on `AXSelectedText` against a collapsed selection inserts at the caret. A web input that accepts a programmatic range and then collapses it turns the whole path into a doubling machine. The range now has to read back as the range we asked for before the `AXSelectedText` write is allowed to run; when it will not, the whole-value write below it is the safe path, because it cannot insert.

## The fallback needs a field it has looked at again

Routing `mangled` to the keystroke path did not fix Cursor, and the log said why in three lines: the first trigger reached `retype` and logged `keys skipped: no selection and no matching mirror`, while the next trigger — same field, same selection, same `retype` — succeeded. The snapshot's range already matched the field's own selection, so `replace` never even called `setRange`. Writing `AXSelectedText` was enough on its own to leave the element unable to answer: truncated value, no selection to confirm, so all of `select`'s attempts fail and the fallback has nothing left to try.

The difference between the failing trigger and the working one was a fresh read of the field. So the fallback takes one before it types.

It cannot always take it immediately. `bestTextElement` keeps the focused element whenever it reports any value at all, so a re-read straight after the write walks back to the same truncated node; in the log Monaco was answering properly again two seconds later. The fallback therefore re-reads at once, uses that if it is usable, and otherwise waits a beat and reads again. Every app that is not Monaco hands back a usable field on the first try and pays nothing.

Usable is a real check, not an assumption: the fresh snapshot is accepted only when it still shows the target selected, or — with no selection to go on — when the target text is still sitting at exactly the range we were about to write. Failing both, the original snapshot is used and the fallback does what it did before, which is to decline rather than type somewhere it cannot vouch for.

## The first trigger in a refusing app is the one that cannot be saved

Re-reading the field was still not enough for Cursor. Polling it for a second and a half sometimes is, but the honest reading of the log is that the first trigger in a refusing app is the hard case and every trigger after it is easy — and they are easy for one reason: `noteRefusal` has run, so `rewrite` returns early and the `AXSelectedText` write that poisons the element never happens. The asymmetry the user saw is exactly that. Attempt one is the only attempt that does the damaging thing.

That reframes the fix. Rather than trying to recover from the write, don't repeat it. The refusal list is now kept in settings instead of being rebuilt each launch, because it is a fact about an app, not about a session: Monaco discarded Accessibility writes yesterday and will discard them tomorrow. Re-learning it every launch charged the user one failed conversion per launch, and for anyone rebuilding the app to test it, that was most of the conversions they attempted.

So the cost is paid once, ever, per app. The recovery poll stays behind it for that one occurrence, and for any app not yet on the list.

The risk of keeping it is an app wrongly marked, which is then stuck on the keystroke path for good. That path works everywhere — it is the only path in terminals — so the failure mode is a slightly less clean rewrite, not a broken one. `defaults delete local.Keyflip axWriteRefused` clears the list if it ever needs clearing.
