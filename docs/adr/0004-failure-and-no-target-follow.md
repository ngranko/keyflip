# Nag permissions on every lapse; toggle the pair when there is no target

Permission prompts are not one-shot. If Accessibility or Input Monitoring is missing, the extra asks again — including after they dismissed the dialog and quit — so it does not fail forever in silence. The prompt is armed by the grant rather than by the launch: rebuilding the ad-hoc-signed bundle revokes the grant of the *running* app while its existing event tap keeps delivering triggers, so a lapse that starts hours into a launch asks again too.

A trigger with **no target** (empty last-word, dead session, no selection) still **follows**: if the current source is in the pair, select the other slot. Marked text and AX failure do **not** follow and do **not** convert. Text rewrite stays AX-only (no clipboard). Expected no-ops stay silent; the layout toggle is the signal when there was no target.
