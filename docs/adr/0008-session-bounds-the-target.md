# The session bounds the target, not just its eligibility

ADR 0002 drew the line at eligibility: a live typing session decides *whether* last-word conversion may run, and the characters still come from the field. That leaves the extent unbounded, and a run of non-whitespace does not have to belong to one session.

Type half of a word, leave the field, come back and finish it in the wrong layout, and the whole run is the target — including the half that was already right. Rewriting text the user never asked about would be bad enough. The vote makes it worse: from-source is decided by counting characters, so a correct prefix longer than the wrong suffix wins the vote and drags the entire word into the layout it was already out of.

Lightroom Classic, from the log: `focal-length-data-` was in the field, the session typed `агдд`, and the trigger turned all of it into `ащсфд-дутпер-вфеф-агдд` and followed to Russian. The user's own fix was to select `агдд` by hand and trigger again. Hyphens are the sharp edge here — they are not whitespace, so a hyphenated identifier is one run no matter how many sessions built it.

So the session bounds the target too. `LastWord.range` takes how much this session typed and never reaches back past where it began: the target is the last run of non-whitespace intersected with the session. Everything else about ADR 0002 stands — a selection still wins outright, and the characters still come from the field, not from the mirror.

The extent is the mirror's length, which is why this is a clip and not a lookup: the mirror can be emptied mid-session by a key that produced no text we could account for. The session is still live then, but where it began is no longer known, so the clip is skipped and the whole run is the target, exactly as before. Clipping to a mirror that has drifted long is handled the same way — the run is left whole rather than trusting a number that cannot be right.

The cost is that finishing a word across a session boundary now converts only the tail. That is the point, but it does mean a user who typed the *whole* word wrong, clicked away and came back cannot fix it with the trigger any more; they have to select it. That was already true after a click under ADR 0002 — the session was dead and the trigger just toggled — so this narrows a case that only ever worked by accident.
