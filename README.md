# Switch Lite

Switch Lite is a small macOS window switcher. The only interface is the panel that appears when you hold Option and press Tab. There is no settings window, menu bar icon, Dock icon, or preview beside the grid.

It is a clean-room app. It does not include AltTab source.

## Build and run

On a Mac with the Xcode command line tools (macOS 12 or later). Put the source in `~/Developer/switch-lite`. `make` creates `~/Applications` if it is missing and installs `~/Applications/SwitchLite.app`. That is the per-user Applications folder, so it does not ask for an admin password.

```sh
xcode-select --install
mkdir -p ~/Developer
cd ~/Developer
git clone <repository-url> switch-lite
cd switch-lite
git checkout cursor/switch-lite-app-f6e4
make
open ~/Applications/SwitchLite.app
```

Run this from `~/Developer/switch-lite`, the folder that contains the `Makefile`. Running `make` in your home folder fails because there is no project there.

`make` compiles with clang, links AppKit, Carbon, ApplicationServices, and CoreGraphics, ad-hoc signs the app, and copies it to `~/Applications/SwitchLite.app`. The bundle id is `app.switchlite.SwitchLite`.

`open` returns immediately. Nothing appears in the Dock. The process stays running until you quit it. Hold Option and press Tab to show the switcher.

The first time Gatekeeper blocks the ad-hoc signature, right-click `~/Applications/SwitchLite.app` and choose Open, or run:

```sh
xattr -dr com.apple.quarantine ~/Applications/SwitchLite.app
```

Switch Lite does not register a login item. To start it at login, add `~/Applications/SwitchLite.app` yourself in System Settings → General → Login Items.

## Shortcuts

Shortcuts are fixed.

| Shortcut | What it does |
|---|---|
| Option-Tab | All windows, most recently focused first. The first Tab selects the previous window. Further Tabs move forward. |
| Option-Shift-Tab | Move backward. The first press selects the last window. |
| Option-grave | Same panel, only windows of the front app. Grave is the ANSI key above Tab on a US keyboard. Shift moves backward. |
| Release Option | Focus the selected window. |
| Esc | Clear the search text first. Esc again cancels and leaves focus where it was. |
| Arrow keys | Move the selection. Left and right move one window. Up and down move one row. |
| Letters and numbers | Filter the grid. Backspace edits the text. |
| W, M, H, Q | While the panel is open and the search text is empty: W closes the selected window, M minimizes it, H hides its app, Q quits that app. |
| Click a cell | Focus that window immediately. |
| Click outside the panel | Cancel. |
| Option-Shift-Q | Quit Switch Lite. This works only while the panel is closed. |

W, M, H, and Q are actions only when the search text is empty. After you type something, those keys edit the search.

## Accessibility

The shortcuts use a `CGEventTap`, and focusing a window uses Accessibility. On launch, macOS asks you to allow Switch Lite to control the computer. There is no custom permission window.

If you dismiss the prompt, turn it on in System Settings → Privacy & Security → Accessibility. The app tries the event tap again every couple of seconds, so you do not need a custom UI after you enable the checkbox. Until Accessibility is on, Option-Tab does nothing.

## Screen Recording

Screen Recording is requested the first time you press Option-Tab (`CGRequestScreenCaptureAccess`), not at launch. macOS may show that dialog before the grid. Allow it if you want window thumbnails. After access is decided, the panel shows immediately with app icons and fills in thumbnails as they are captured.

If you deny it, or the prompt is still unanswered, each cell shows that app’s icon and the owner name. You can turn Screen Recording on later in System Settings → Privacy & Security → Screen Recording, then open the switcher again.

## Memory

Idle memory should sit near a small AppKit process, about 15–25 MB, because screenshots are not kept.

- The only timer stores the front window id, about twice a second. It does not store images.
- App icons are drawn down to 32 points and cached. The full-size icon is released.
- Thumbnails are captured only while the panel is visible, one window at a time, at nominal resolution, then scaled to a bitmap at most 400 pixels on the long side. The full frame is released before the next window is captured.
- When the panel closes, every thumbnail is set to nil and layer contents are cleared. Nothing is kept for the next time you open it.

That 15–25 MB figure is the size to expect from AppKit itself while the switcher is closed. It is not a claim that the process measures under 10 MB. Confirm it on your Mac in Activity Monitor (Memory) with the panel closed and with it open.

## Quit

Hold Option and Shift and press Q while the panel is closed. You can also quit `SwitchLite` from Activity Monitor.
