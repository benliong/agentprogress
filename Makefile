.PHONY: build build-release cli app install-cli clean test

# Build everything (debug)
build:
	swift build

# Build release binaries
build-release:
	swift build -c release

# Build just the CLI (release) and symlink to /usr/local/bin
cli: build-release
	ln -sf "$(shell swift build -c release --show-bin-path)/progress" /usr/local/bin/progress
	@echo "Installed: /usr/local/bin/progress"

# Package the menu bar app into a .app bundle
app: build-release
	@BIN=$$(swift build -c release --show-bin-path)/ProgressMenuBar; \
	APP=.build/ProgressMenuBar.app; \
	CONTENTS=$$APP/Contents; \
	mkdir -p $$CONTENTS/MacOS $$CONTENTS/Resources; \
	cp $$BIN $$CONTENTS/MacOS/ProgressMenuBar; \
	printf '<?xml version="1.0" encoding="UTF-8"?>\n\
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
	<plist version="1.0"><dict>\n\
	  <key>CFBundleIdentifier</key><string>engineering.happy.ProgressMenuBar</string>\n\
	  <key>CFBundleName</key><string>ProgressMenuBar</string>\n\
	  <key>CFBundlePackageType</key><string>APPL</string>\n\
	  <key>CFBundleShortVersionString</key><string>1.0</string>\n\
	  <key>CFBundleVersion</key><string>1</string>\n\
	  <key>CFBundleExecutable</key><string>ProgressMenuBar</string>\n\
	  <key>LSUIElement</key><true/>\n\
	  <key>NSHighResolutionCapable</key><true/>\n\
	  <key>NSPrincipalClass</key><string>NSApplication</string>\n\
	</dict></plist>' > $$CONTENTS/Info.plist; \
	@echo "Built: $$APP"
	@echo "To launch: open .build/ProgressMenuBar.app"

# Run tests
test:
	swift test

clean:
	swift package clean
