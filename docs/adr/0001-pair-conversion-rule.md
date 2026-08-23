# Detect from-source from the text; follow even when nothing changed

Conversion direction is not “current input source → the other of the pair.” The extra counts **votes** (a character votes for a source only if it inverts there and not on the other), takes the winner as from-source, and rewrites toward the other member. Ties use the current source when it is in the pair; otherwise the trigger is a no-op.

Unmapped characters, Option-only characters, and dead-key-only letters are left unchanged. Invert uses unshifted and Shift only; simplest physical key on collisions inside that set. Follow selects the destination whenever conversion ran, including when no character changed, and does not try to cooperate with per-document input-source switching.

The obvious alternative — always convert from the currently selected source — fails on a selection typed earlier, after the user has already followed or switched by hand.
