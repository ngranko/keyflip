#!/bin/bash
set -euo pipefail
binary=${1:-.build/universal/Keyflip}
plist=${2:-App/Info.plist}
minimum=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist")
if [ "$minimum" != '13.0' ]; then
  echo 'Expected macOS 13.0 minimum; update the support policy and build targets together.' >&2
  exit 1
fi
for architecture in arm64 x86_64; do
  lipo "$binary" -verify_arch "$architecture"
  actual=$(otool -arch "$architecture" -l "$binary" | awk '$1 == "minos" { print $2 }')
  if [ "$actual" != "$minimum" ]; then
    echo "$architecture requires macOS $actual; declared minimum is $minimum." >&2
    exit 1
  fi
done
echo 'Verified arm64 and x86_64, each targeting macOS 13.0.'
