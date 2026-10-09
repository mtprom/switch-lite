# Build SwitchLite.app on macOS. Needs the Xcode command line tools (clang).

UNAME_S := $(shell uname -s)
ifneq ($(UNAME_S),Darwin)
$(error Switch Lite must be built on macOS. This host is $(UNAME_S).)
endif

APP := SwitchLite.app
BIN := $(APP)/Contents/MacOS/SwitchLite
# Per-user Applications, not /Applications, so install does not need an admin password.
DEST := $(HOME)/Applications/$(APP)

SRCS := \
	src/main.m \
	src/SLImage.m \
	src/SLWindow.m \
	src/SLMRU.m \
	src/SLIconCache.m \
	src/SLFocus.m \
	src/SLCapture.m \
	src/SLPanel.m \
	src/SLEventTap.m \
	src/SLSession.m \
	src/SLAppDelegate.m

CFLAGS := -fobjc-arc -Wall -Wextra -Os -mmacosx-version-min=12.0 -Isrc
LIBS := -framework AppKit -framework Carbon -framework ApplicationServices -framework CoreGraphics

.PHONY: all clean install uninstall

all: install

install: $(BIN)
	mkdir -p $(HOME)/Applications
	rm -rf $(DEST)
	cp -R $(APP) $(DEST)
	@echo "Installed $(DEST)"

uninstall:
	rm -rf $(DEST)

$(BIN): $(SRCS) Info.plist
	mkdir -p $(APP)/Contents/MacOS
	clang $(CFLAGS) $(LIBS) -o $(BIN) $(SRCS)
	cp Info.plist $(APP)/Contents/Info.plist
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - $(APP)

clean:
	rm -rf $(APP)
