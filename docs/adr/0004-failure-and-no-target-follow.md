# Nag permissions on every launch; toggle the pair when there is no target

Permission prompts are not one-shot. If Accessibility or Input Monitoring is still missing, the extra asks again on **each launch** — including after they dismissed the dialog and quit — so it does not fail forever in silence.

A trigger with **no target** (empty last-word, dead session, no selection) still **follows**: if the current source is in the pair, select the other slot. Marked text and AX failure do **not** follow and do **not** convert. Text rewrite stays AX-only (no clipboard). Expected no-ops stay silent; the layout toggle is the signal when there was no target.
