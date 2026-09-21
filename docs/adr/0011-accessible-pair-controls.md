# Restore the pair columns with accessible controls

The menu again shows both layout columns and the trigger and launch-at-login pills. Picking a layout updates both columns without closing the menu. Unsupported layouts and the layout selected in the opposite column remain disabled.

The custom controls expose accessibility roles, names, values, enabled states, and press actions. Layout names include their slot for screen readers, while the visible columns remain unlabeled. Layer colors continue to refresh when the system appearance changes.

The duplicate Settings submenu is removed. Custom menu views accept first-responder status. Up/Down uses AppKit navigation between menu sections; Left/Right moves through enabled controls within a section in row order. Return or Space activates the focused control, and Escape dismisses the menu. A focus outline follows keyboard navigation and mouse hover. No event monitor or keyboard tap is needed.

Quit uses a dedicated action forwarding to application termination so AppKit does not add a standard action icon and indent the footer for its image column. The Command-Q shortcut remains available.

Setup, monitoring recovery, diagnostics, and launch-at-login error handling remain available. The login pill reports when system approval is needed.
