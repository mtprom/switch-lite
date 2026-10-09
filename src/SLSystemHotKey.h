#import <Foundation/Foundation.h>

// While Switch Lite is running, macOS Cmd-Tab (and Cmd-Shift-Tab) is turned off.
// Quit restores the previous enabled state. A crash marker is applied on the
// next launch so a missed quit does not leave Cmd-Tab disabled.
void SLRecoverInterruptedCommandTab(void);
void SLDisableSystemCommandTab(void);
void SLRestoreSystemCommandTab(void);
