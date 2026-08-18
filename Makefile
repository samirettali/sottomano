APP_NAME := Sottomano
CONFIG   ?= release
BUNDLE   := dist/$(APP_NAME).app
BINARY   := .build/$(CONFIG)/$(APP_NAME)

.PHONY: build bundle run dev clean

build:
	swift build -c $(CONFIG)

# LSUIElement lives in Info.plist, so a bare `swift run` binary is not the
# shipped app: it would take a Dock icon and the activation policy with it.
bundle: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Packaging/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	codesign --force --sign - $(BUNDLE)

# Two instances mean two hotkey registrations, and the second one loses, so the
# running copy has to go before the new one starts.
run: bundle
	pkill -x $(APP_NAME) || true
	open $(BUNDLE)

dev:
	$(MAKE) run CONFIG=debug

clean:
	rm -rf .build dist
