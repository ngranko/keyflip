<p align="center">
  <img src="docs/assets/icon.png" alt="Keyflip" width="128" height="128">
</p>

<h1 align="center">Keyflip</h1>
<div align="center">Recover your text written in a wrong layout</div>

## About

I was really tired that all switchers that I'd tried worked like shit (crashing, switching to wrong symbols, swallowing my keypresses, you get the picture), so here we are, now we have n+1 competing switcher apps.

Yes, this one is fully AI-generated (I'm not that proficient in swift) and no, I don't plan to get any money out of it. I've created it just to fix my personal pain point. If it helps anyone else – cool, if someone decides to improve it – even better (although please read the Contributing section beforehand).

## Contributing

The app is MIT licensed, so you are free to fork it and do with it as you please. Or you can file an issue or a PR if you want the base app to get better. But be aware: I very consciously made it a utility that does one thing and one thing only and don't plan to turn it into a swiss-army knife of an app. So I will close all PRs and issues that I deem not relevant to the core functionality.

## Conversion support

Keyflip converts characters on the base and Shift layers of keyboard layouts.
Option-layer characters, dead-key sequences, multi-character key outputs, and
IME composition are not supported. Characters without a supported mapping stay
unchanged. A terminal rewrite uses only text observed during an uninterrupted
typing session; text entered before launch or before moving the caret must be
retyped or selected in a field that exposes its selection.

Terminal writes are best effort because terminals do not confirm their contents.
Keyflip skips fields over 65,536 UTF-16 units and synthesized replacements over
4,096 UTF-16 units. The debug log records outcomes and session reset reasons,
never the text being converted.

## Install and get started

Keyflip targets macOS 13 or later on Intel and Apple Silicon. Public releases
contain both architectures. See [support and release checks](docs/support.md)
for the automated checks and the manual compatibility checks still required.

Move Keyflip to Applications and open it. The setup window explains Accessibility
access, lets you choose two layouts and your trigger, and provides a practice
field. The default trigger is a double-tap of Option. Type a word using the wrong
layout, then trigger conversion; select older text before converting it.

You can reopen **Set up Keyflip…** from the menu bar at any time. Setup refreshes
when permissions change, so granting access does not require a restart. The
current self-signed releases still require **Open Anyway** in System Settings
under Privacy & Security on first launch.

## Troubleshooting and privacy

If conversion does nothing, reopen setup to check Accessibility, your layout
pair, and keyboard monitoring. Launch-at-login errors now explain how to check
Login Items in System Settings.

**Copy diagnostic report** copies the app/build version, macOS version, process
architecture, layout IDs, permission and monitoring states, and recent logs.
Reports can contain application names and timestamps, but no converted text;
your home directory is replaced with `~`. Nothing is uploaded automatically.
Keyflip processes text locally, keeps a short typing buffer in memory, and does
not save the setup practice field.
