# Build SwitchLite.app on macOS. Needs the Xcode command line tools (clang).

UNAME_S := $(shell uname -s)
ifneq ($(UNAME_S),Darwin)
$(error Switch Lite must be built on macOS. This host is $(UNAME_S).)
endif

APP := SwitchLite.app
BIN := $(APP)/Contents/MacOS/SwitchLite

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
	src/SLSystemHotKey.m \
	src/SLAppDelegate.m

CFLAGS := -fobjc-arc -Wall -Wextra -Os -mmacosx-version-min=12.0 -Isrc
LIBS := -framework AppKit -framework Carbon -framework ApplicationServices -framework CoreGraphics

.PHONY: all clean

all: $(BIN)

$(BIN): $(SRCS) Info.plist SwitchLite.icns
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	clang $(CFLAGS) $(LIBS) -o $(BIN) $(SRCS)
	cp Info.plist $(APP)/Contents/Info.plist
	cp SwitchLite.icns $(APP)/Contents/Resources/SwitchLite.icns
	printf 'APPL????' > $(APP)/Contents/PkgInfo
	codesign --force --sign - $(APP)

clean:
	rm -rf $(APP)
