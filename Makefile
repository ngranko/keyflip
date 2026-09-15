SWIFT := swift
SWIFT_FLAGS ?=
APP := .build/Keyflip.app
ZIP := Keyflip.zip
UNIVERSAL_BIN := .build/universal/Keyflip

# TCC pins the Accessibility grant to whatever identity signed the bundle, so a
# stable certificate keeps the grant across rebuilds where ad-hoc signing re-pins
# it to each new cdhash. Falls back to ad-hoc so a fork without the cert builds.
# See docs/signing.md.
SIGN_ID ?= Keyflip Self-Signed
IDENTITY = $(shell security find-identity -p codesigning | grep -qF "$(SIGN_ID)" && echo "$(SIGN_ID)" || echo -)

.PHONY: test build build-universal verify-universal app sign run install clean icon glass zip archive

test:
	$(SWIFT) test $(SWIFT_FLAGS)

build:
	$(SWIFT) build -c release $(SWIFT_FLAGS)

# Separate builds also work with Command Line Tools, without Xcode's build service.
build-universal:
	@set -eu; for arch in arm64 x86_64; do \
		$(SWIFT) build -c release --product Keyflip --triple "$$arch-apple-macosx13.0" --scratch-path ".build/release-$$arch" $(SWIFT_FLAGS); \
	done
	mkdir -p .build/universal
	@set -eu; \
	arm=$$($(SWIFT) build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/release-arm64 $(SWIFT_FLAGS) --show-bin-path); \
	intel=$$($(SWIFT) build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/release-x86_64 $(SWIFT_FLAGS) --show-bin-path); \
	lipo -create "$$arm/Keyflip" "$$intel/Keyflip" -output $(UNIVERSAL_BIN)
	@$(MAKE) --no-print-directory verify-universal

verify-universal:
	bash Tools/release/verify-support.sh $(UNIVERSAL_BIN)

app: build-universal
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(UNIVERSAL_BIN) $(APP)/Contents/MacOS/Keyflip
	cp App/Info.plist $(APP)/Contents/Info.plist
	@if [ -f App/Keyflip.icns ]; then \
		mkdir -p $(APP)/Contents/Resources; \
		cp App/Keyflip.icns $(APP)/Contents/Resources/Keyflip.icns; \
	fi
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	@$(MAKE) --no-print-directory sign

# Its own target so `app` and `glass` cannot drift into signing differently.
sign:
	@[ "$(IDENTITY)" != "-" ] || echo 'warning: no "$(SIGN_ID)" identity in the keychain; signing ad-hoc, which drops the Accessibility grant on every build'
	codesign --force --sign "$(IDENTITY)" --identifier local.Keyflip --timestamp=none $(APP)

run: app
	open $(APP)

install: app
	rm -rf /Applications/Keyflip.app
	cp -R $(APP) /Applications/Keyflip.app

# Re-render App/Keyflip.icns and the Icon Composer layers from one geometry.
icon:
	$(SWIFT) Tools/AppIcon/generate.swift

# Build the bundle with the macOS 26 Liquid Glass icon instead of the flat .icns.
# Assets.car carries the layered icon; the .icns stays as the pre-26 fallback.
glass: app
	rm -rf .build/icon && mkdir -p .build/icon
	actool App/Keyflip.icon --compile .build/icon --platform macosx \
		--minimum-deployment-target 26.0 --app-icon Keyflip \
		--output-partial-info-plist .build/icon/partial.plist >/dev/null
	cp .build/icon/Assets.car $(APP)/Contents/Resources/Assets.car
	plutil -replace CFBundleIconName -string Keyflip $(APP)/Contents/Info.plist
	@$(MAKE) --no-print-directory sign

# Zip the built bundle to $(ZIP) in the repo root. ditto (not zip) so the
# symlinks and xattrs the code signature depends on survive the archive.
zip: app
	@$(MAKE) --no-print-directory archive

# Archive whatever is already in $(APP), without rebuilding it.
# Use this after `make glass` so the Assets.car icon is not clobbered.
archive:
	rm -f $(ZIP)
	ditto -c -k --keepParent --sequesterRsrc $(APP) $(ZIP)

clean:
	rm -rf .build $(APP) $(ZIP)
