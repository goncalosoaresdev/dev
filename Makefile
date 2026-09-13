SCHEME := Dev
DERIVED := build
APP := $(DERIVED)/Build/Products/Debug/Dev.app
INSTALL_APP := /Applications/Dev.app
IDENTITY := -
REQ := =designated => identifier "com.goncalosoares.Dev"

.PHONY: build run install test open clean resign

build:
	xcodebuild -project Dev.xcodeproj -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="$(IDENTITY)" CODE_SIGNING_REQUIRED=NO \
		ENABLE_DEBUG_DYLIB=NO ENABLE_PREVIEWS=NO \
		build
	$(MAKE) resign

resign:
	codesign --force --sign "$(IDENTITY)" \
		--identifier com.goncalosoares.Dev \
		--entitlements Dev/Dev.entitlements \
		--requirements '$(REQ)' \
		"$(APP)"
	codesign -d -r- "$(APP)"

run: install

install: build
	@killall Dev 2>/dev/null || true
	rm -rf "$(INSTALL_APP)"
	cp -R "$(APP)" "$(INSTALL_APP)"
	codesign --force --sign "$(IDENTITY)" \
		--identifier com.goncalosoares.Dev \
		--entitlements Dev/Dev.entitlements \
		--requirements '$(REQ)' \
		"$(INSTALL_APP)"
	open "$(INSTALL_APP)"

test:
	xcodebuild -project Dev.xcodeproj -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY="$(IDENTITY)" CODE_SIGNING_REQUIRED=NO \
		ENABLE_DEBUG_DYLIB=NO \
		test -destination 'platform=macOS,arch=arm64'

open:
	open Dev.xcodeproj

clean:
	rm -rf $(DERIVED)
