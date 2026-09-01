# Signing

Keyflip is signed with a long-lived self-signed certificate rather than ad-hoc.

## Why

Keyflip needs Accessibility to create its event tap. TCC stores that grant
against the bundle's *designated requirement*, and how that requirement is
written depends on how the bundle was signed:

| Signing | Designated requirement |
| --- | --- |
| ad-hoc (`codesign --sign -`) | `cdhash H"…"` |
| certificate | `identifier "local.Keyflip" and certificate root = H"…"` |

A cdhash changes with every build, so an ad-hoc bundle lost its Accessibility
grant on every `make install` — silently, leaving an app that launched and did
nothing. Pinned to a certificate instead, the requirement holds across rebuilds
and across releases, so the grant is given once.

This is also what makes an auto-updater viable: an update that swapped the
binary under an ad-hoc signature would quietly break the app for every user.

It does *not* help with Gatekeeper. A self-signed certificate cannot be
notarized, so the first launch after download still needs the release note's
System Settings → Privacy & Security → Open Anyway.

## Setup

One machine holds the certificate; everything else reads it from the keychain
or from CI secrets.

```sh
Tools/signing/create-certificate.sh
```

That writes the identity into your login keychain and prints paths to a
base64-encoded `.p12` and its password. Set both as repository secrets:

- `SIGNING_CERTIFICATE_P12`
- `SIGNING_CERTIFICATE_PASSWORD`

Then back the pair up somewhere durable. The certificate is the app's identity:
lose it and every existing user has to re-grant Accessibility once against
whatever replaces it. It expires ten years out, and because the signature is not
timestamped, renewing it is the same one-time cost for users.

## How the build uses it

`make sign` signs `$(APP)` with `$(SIGN_ID)`, defaulting to `Keyflip Self-Signed`.
`app` and `glass` both call it, and so does the release workflow after it stamps
the version into `Info.plist`. When no such identity is in the keychain — a
fork, a fresh checkout — it falls back to ad-hoc signing with a warning, so the
build still works and only the grant stability is lost.

## Verifying

```sh
codesign -d -r- --verbose=2 .build/Keyflip.app
```

The `designated =>` line should name a certificate, not a cdhash.
