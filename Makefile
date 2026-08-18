APP_NAME := Sottomano
CONFIG   ?= release
BUNDLE   := dist/$(APP_NAME).app
BINARY   := .build/$(CONFIG)/$(APP_NAME)

# Developer ID on development builds too, as Pulse does, and here it is not
# only for consistency: an ad-hoc signature changes with every build, so TCC
# sees a different application each time and the Accessibility grant silently
# stops applying. The caps lock tap needs that grant.
SIGN_IDENTITY ?= Developer ID Application

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
	@identity="$(SIGN_IDENTITY)"; timestamp="--timestamp"; \
	if ! security find-identity -p codesigning | grep -q "$$identity"; then \
		echo "warning: '$$identity' not found — ad-hoc signing, and Accessibility will not stick"; \
		identity="-"; timestamp="--timestamp=none"; \
	fi; \
	set -x; \
	codesign --force --options runtime $$timestamp --sign "$$identity" $(BUNDLE)

# Two instances mean two hotkey registrations, and the second one loses, so the
# running copy has to go before the new one starts.
run: bundle
	pkill -x $(APP_NAME) || true
	open $(BUNDLE)

dev:
	$(MAKE) run CONFIG=debug

clean:
	rm -rf .build dist
