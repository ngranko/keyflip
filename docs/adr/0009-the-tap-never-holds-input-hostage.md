# The tap never holds input hostage

A tap that may delete events is a promise to answer every one in its mask, and a promise this process cannot always keep. Unticking Keyflip in Accessibility twice cost the machine its keyboard and every mouse click, while the pointer went on moving — pointer movement is not in the mask, which is the fault's signature.

Two things the log settled, both of which had looked obvious the other way:

**Re-enabling a disabled tap is what makes a lockout last.** `tapDisabledByTimeout` is macOS handing the user back their input. The first incident ends on two `tap re-enabled after timeout` lines, eleven seconds apart, each one taking the keyboard away again.

**`AXIsProcessTrusted` cannot be asked whether the grant is gone.** Through thirty seconds of dead input in the second incident it kept answering yes — the process was logging `while trusted` after the checkbox had been off for half a minute. It reports a *grant* arriving, and that is all it is good for. What the window server will actually build is the only honest answer, so the tap is its own probe: try to create one, and take a refusal as the grant being gone.

The rule above every feature: **an event this app cannot deal with right now goes through untouched, and a tap it cannot answer stops existing.**

**The tap may only listen unless something needs deleting.** A listening tap cannot hold anyone's keyboard, whatever state this process is in. Exactly two things need more — a chord trigger, whose key must fire without also typing its character, and the Set-trigger panel, which swallows keys so binding ⌘Q does not quit the app underneath it. A double-tap trigger, the default, deletes nothing ever. A tap cannot be granted new powers, only replaced by one that has them.

**The listening tap is preflighted, never requested.** Creating one raises the Input Monitoring dialog, which is what made the app appear to want two grants. It does not: measured on macOS 26, `CGPreflightListenEventAccess` answers true for this app with its `ListenEvent` row reset to undecided, and false for a process without Accessibility — the access rides on the Accessibility grant Keyflip must have anyway to read a field. So the dialog is noise; decline it, remove the row, and the safe tap is still what runs. The preflight stays because it is the honest question, and because the day a macOS separates the two services this degrades to an active tap on its own instead of failing to build one at all. Keyflip asks for one grant, and that grant is Accessibility.

**Keys the system counts but the tap is never handed mean it is holding them.** The HID layer stamps a keystroke the moment it is pressed, upstream of any tap, so a system that has seen a key in the last two seconds while the tap has seen none for more than two seconds is a tap holding input. It is the only symptom of this fault visible from anywhere, because the callback cannot report a condition whose definition is that the callback is not running — which is why every earlier defence, all of them inside the callback or inside a trust API, missed both incidents. The supervisor checks it every tick and takes the tap away. Secure input withholds keys from every tap by design and is excluded.

**A timeout tears the tap down.** Never re-enabled in place. The supervisor builds a fresh one a second or two later, which is also the trust probe. A second timeout inside the minute is a pattern rather than a hiccup, and the tap stays gone until a person grants the permission again — nothing automatic revives it.

**The tap is answered on its own thread.** Every AX call blocks for up to a second and several run per trigger, all on the main thread. A tap serviced from that same thread is one stalled app away from eating a keystroke.

**Nothing in the callback waits.** The lock over the recognizer and the recorder is only ever tried, never taken: if the main thread holds it, the event passes through unconverted. Swallowing keys for the Set-trigger panel expires on its own, so a panel that outlives its window cannot keep the keyboard.

These bound a stall rather than preventing one, and they are what the app falls back on whenever it must run a tap that can delete: a chord trigger, the Set-trigger panel, or a system that refuses to let it merely listen. The tap can hold keys until whichever comes first — the accessibility-list notification, the watchdog two seconds on, or the window server's own timeout — and a second strike inside the minute retires it for the launch. Where the listening tap is available, which is everywhere Accessibility is granted, there is nothing to bound: it holds nothing.

A missed conversion is an annoyance. A keystroke this app is holding is not.
