#import "SLSystemHotKey.h"

#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

// SkyLight symbolic hotkeys: 1 is Cmd-Tab, 2 is Cmd-Shift-Tab.
static const int kCommandTabHotKeys[] = {1, 2};
static const int kCommandTabHotKeyCount = 2;

typedef int (*SLSetHotKeyFn)(int hotKey, int enabled);
typedef int (*SLIsHotKeyFn)(int hotKey);

static SLSetHotKeyFn gSetHotKey;
static SLIsHotKeyFn gIsHotKey;
static int gSaved[2];
static int gDisabled;
static int gRestored;
static char gMarkerPath[1024];
static int gSignalsHooked;

static void SLLoadHotKeyAPI(void) {
    if (gSetHotKey && gIsHotKey) return;
    void *sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    if (!sky) return;
    gSetHotKey = (SLSetHotKeyFn)dlsym(sky, "CGSSetSymbolicHotKeyEnabled");
    gIsHotKey = (SLIsHotKeyFn)dlsym(sky, "CGSIsSymbolicHotKeyEnabled");
}

static int SLMarkerReady(void) {
    if (gMarkerPath[0] != '\0') return 1;
    const char *home = getenv("HOME");
    if (!home || home[0] == '\0') return 0;
    char dir[1024];
    int wrote = snprintf(dir, sizeof(dir), "%s/Library/Application Support/Switch Lite", home);
    if (wrote < 0 || (size_t)wrote >= sizeof(dir)) return 0;
    mkdir(dir, 0755);
    wrote = snprintf(gMarkerPath, sizeof(gMarkerPath), "%s/command-tab-hotkey", dir);
    if (wrote < 0 || (size_t)wrote >= sizeof(gMarkerPath)) {
        gMarkerPath[0] = '\0';
        return 0;
    }
    return 1;
}

static void SLApplyHotKeys(const int *enabled) {
    if (!gSetHotKey) return;
    for (int i = 0; i < kCommandTabHotKeyCount; i++) {
        gSetHotKey(kCommandTabHotKeys[i], enabled[i] ? 1 : 0);
    }
}

static int SLReadMarker(int *enabled) {
    if (!SLMarkerReady()) return 0;
    FILE *file = fopen(gMarkerPath, "r");
    if (!file) return 0;
    for (int i = 0; i < kCommandTabHotKeyCount; i++) {
        int hotKey = 0;
        int on = 0;
        if (fscanf(file, "%d %d", &hotKey, &on) != 2 || hotKey != kCommandTabHotKeys[i]) {
            fclose(file);
            return 0;
        }
        enabled[i] = on ? 1 : 0;
    }
    fclose(file);
    return 1;
}

static void SLWriteMarker(const int *enabled) {
    if (!SLMarkerReady()) return;
    FILE *file = fopen(gMarkerPath, "w");
    if (!file) return;
    for (int i = 0; i < kCommandTabHotKeyCount; i++) {
        fprintf(file, "%d %d\n", kCommandTabHotKeys[i], enabled[i] ? 1 : 0);
    }
    fclose(file);
}

static void SLRemoveMarker(void) {
    if (!SLMarkerReady()) return;
    unlink(gMarkerPath);
}

void SLRecoverInterruptedCommandTab(void) {
    SLLoadHotKeyAPI();
    int saved[2];
    if (!SLReadMarker(saved)) return;
    SLApplyHotKeys(saved);
    SLRemoveMarker();
}

void SLRestoreSystemCommandTab(void) {
    if (gRestored || !gDisabled) return;
    gRestored = 1;
    SLLoadHotKeyAPI();
    SLApplyHotKeys(gSaved);
    SLRemoveMarker();
    gDisabled = 0;
}

static void SLAtExit(void) {
    SLRestoreSystemCommandTab();
}

static void SLOnSignal(int sig) {
    SLRestoreSystemCommandTab();
    signal(sig, SIG_DFL);
    raise(sig);
}

void SLDisableSystemCommandTab(void) {
    if (gDisabled) return;
    SLLoadHotKeyAPI();
    if (!gSetHotKey) {
        NSLog(@"Switch Lite: could not turn off the system Command-Tab shortcut.");
        return;
    }
    SLRecoverInterruptedCommandTab();
    for (int i = 0; i < kCommandTabHotKeyCount; i++) {
        gSaved[i] = gIsHotKey ? (gIsHotKey(kCommandTabHotKeys[i]) ? 1 : 0) : 1;
    }
    SLWriteMarker(gSaved);
    int off[2] = {0, 0};
    SLApplyHotKeys(off);
    gDisabled = 1;
    gRestored = 0;
    if (!gSignalsHooked) {
        atexit(SLAtExit);
        signal(SIGTERM, SLOnSignal);
        signal(SIGINT, SLOnSignal);
        signal(SIGHUP, SLOnSignal);
        gSignalsHooked = 1;
    }
}
