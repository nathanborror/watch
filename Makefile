APP_NAME  := Watch
BUNDLE_ID := work.hungryfoolish.Watch
PREFIX    ?= /Applications

APP  := .build/$(APP_NAME).app
DEST := $(PREFIX)/$(APP_NAME).app

.PHONY: run app install uninstall clean

## Build and run the debug build from the terminal.
run:
	swift run $(APP_NAME)

## Build a release Watch.app in .build/.
app:
	swift build -c release
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Support/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign - "$(APP)"

## Build Watch.app and copy it to $(PREFIX) (default /Applications).
## Refuses to replace a Watch.app that isn't this one.
install: app
	@if [ -d "$(DEST)" ] && [ "$$(defaults read "$(abspath $(DEST))/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$(BUNDLE_ID)" ]; then \
		echo "$(DEST) exists and isn't this Watch; not replacing it."; exit 1; \
	fi
	mkdir -p "$(PREFIX)"
	rm -rf "$(DEST)"
	cp -R "$(APP)" "$(DEST)"
	@echo "Installed $(DEST)"

uninstall:
	@if [ -d "$(DEST)" ] && [ "$$(defaults read "$(abspath $(DEST))/Contents/Info" CFBundleIdentifier 2>/dev/null)" = "$(BUNDLE_ID)" ]; then \
		rm -rf "$(DEST)" && echo "Removed $(DEST)"; \
	else \
		echo "No Watch.app at $(DEST)"; \
	fi

clean:
	swift package clean
	rm -rf "$(APP)"
