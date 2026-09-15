# Supported systems and release checks

Keyflip targets macOS 13 Ventura and later on Apple Silicon and Intel Macs.
Public app bundles contain both arm64 and x86_64 executables. Rosetta is not
required. `make app` builds both architectures; `make build` builds only for the
development machine. The optional Liquid Glass icon requires macOS 26 tooling;
the standard icon remains available on older systems.

`make build-universal` compiles each architecture against a macOS 13.0 deployment
target and joins them with lipo. `Tools/release/verify-support.sh` checks both
slices and their minimum OS against the bundle metadata. The release workflow
runs this check on the actual packaged app.

Pull requests and release jobs run the same CI test suite on macOS 15 for both architectures and macOS 26 on Apple
Silicon. It also builds and verifies a universal executable. CI does not establish
runtime compatibility with macOS 13 or 14; those remain manual release checks.

Before publishing, test the downloaded release archive on macOS 13 and the
current macOS release, including an Intel Mac and an Apple Silicon Mac. Record
the app version, OS version, processor, and results in the release notes. Do not
claim a system was tested when only compilation was checked.

For each release, check:

- First launch with no permission, permission approval, dismissal of setup, and
  reopening setup from the menu. Confirm setup completes only when ready.
- Two layouts, a missing layout, trigger recording, and conversion in the
  setup practice field.
- Fresh typing and selected text in a native field, browser, Electron editor,
  Terminal, and cmux. Include spaces, rapid triggers, caret movement, and Undo.
- Sleep/wake, revoking and restoring Accessibility, and launch-at-login approval.
- Both architectures in the downloaded archive, and a diagnostic report that
  includes build details without practice text or the user's home directory.

These are manual smoke tests of operating-system and editor integration, in
addition to the automated tests.
