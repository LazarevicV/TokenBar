.PHONY: build test app run install dist check-bundle clean icon scan-secrets

# With Command Line Tools only (no Xcode), the Swift Testing macro plugin lives in a
# subdirectory that `swift test` does not search. Pass it explicitly when present.
TESTING_PLUGINS := $(shell xcode-select -p 2>/dev/null)/usr/lib/swift/host/plugins/testing
ifneq ($(wildcard $(TESTING_PLUGINS)),)
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS)
endif

build:
	swift build

test:
	swift test $(TEST_FLAGS)

app:
	./scripts/bundle.sh

run: app
	open build/TokenBar.app

# Build and copy TokenBar.app into /Applications (INSTALL_DIR=~/Applications to override).
install:
	./scripts/install.sh

# build/TokenBar-<version>.zip for GitHub Releases and the Homebrew cask.
dist: app
	./scripts/dist.sh

check-bundle:
	./scripts/check-bundle.sh

scan-secrets:
	./scripts/scan-secrets.sh

clean:
	rm -rf build .build

# Regenerate Resources/AppIcon.icns from assets/tokenbar-logo-app-icon.png
icon:
	swift scripts/make-icon.swift assets/tokenbar-logo-app-icon.png build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
