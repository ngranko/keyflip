SWIFT := swift
APP := .build/Keyflip.app
BIN := $(shell $(SWIFT) build -c release --show-bin-path)/Keyflip

.PHONY: test build app run install clean icon glass

test:
	$(SWIFT) test

build:
	$(SWIFT) build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/Keyflip
	cp App/Info.plist $(APP)/Contents/Info.plist
	@if [ -f App/Keyflip.icns ]; then \
		mkdir -p $(APP)/Contents/Resources; \
		cp App/Keyflip.icns $(APP)/Contents/Resources/Keyflip.icns; \
	fi
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - --identifier local.Keyflip --timestamp=none $(APP)

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
	codesign --force --sign - --identifier local.Keyflip --timestamp=none $(APP)

clean:
	rm -rf .build $(APP)
