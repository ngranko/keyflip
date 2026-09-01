#!/usr/bin/env bash
# Creates the stable code signing identity Keyflip signs with. TCC pins the
# Accessibility grant to the signing certificate, so one long-lived cert keeps
# the grant across rebuilds. Run once; see docs/signing.md.
set -euo pipefail

NAME="${SIGN_ID:-Keyflip Self-Signed}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
DIR="$(mktemp -d)"

if security find-identity -p codesigning | grep -qF "$NAME"; then
  echo "error: an identity named \"$NAME\" already exists; remove it in Keychain Access first" >&2
  exit 1
fi

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" \
  -subj "/CN=$NAME/O=Keyflip" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl rand -base64 24 > "$DIR/password.txt"
openssl pkcs12 -export -legacy -inkey "$DIR/key.pem" -in "$DIR/cert.pem" \
  -name "$NAME" -out "$DIR/certificate.p12" -passout "file:$DIR/password.txt"

security import "$DIR/certificate.p12" -k "$KEYCHAIN" \
  -P "$(cat "$DIR/password.txt")" -T /usr/bin/codesign
# codesign signs happily with an untrusted certificate, but Keychain Access and
# `security find-identity -v` only list it once the self-signed root is trusted.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$DIR/cert.pem"

base64 < "$DIR/certificate.p12" > "$DIR/certificate.p12.base64"
rm "$DIR/key.pem" "$DIR/cert.pem"

cat <<EOF

Identity "$NAME" is in your login keychain. \`make app\` will now use it.

Back these up, then set them as GitHub Actions secrets:
  SIGNING_CERTIFICATE_P12       $DIR/certificate.p12.base64
  SIGNING_CERTIFICATE_PASSWORD  $DIR/password.txt

Losing the certificate means every user has to re-grant Accessibility once.
EOF
