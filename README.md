# MenuBoard

A macOS menu bar utility (Swift, AppKit + SwiftUI, no dependencies).

- **System** – CPU (total + per core), memory breakdown, swap, memory pressure, disk, battery, uptime, thermal state.
- **Memory** – physical footprint per app, grouped the way Activity Monitor does (helpers roll up into their parent app). Right-click to quit / force quit.
- **Audio** – output device volume and **per-app volume / mute**.
- **Shelf** – temporary holder for files, links and web images. Start dragging anything and a drop zone slides
  out under the menu bar icon; you can also drop on the icon itself or anywhere in the popover. Drag items back
  out one by one or all at once.
- **Menu bar readout** – optionally show CPU %, memory used, memory %, battery or free disk in the menu bar,
  next to or instead of the icon (gear menu or right-click the icon → Show in Menu Bar).
- **Clips** – clipboard history (text, files, images) with the source app, search, click-to-copy and a record toggle.
  Entries marked concealed/transient by password managers are never recorded. Up to 200 entries, stored in
  `~/Library/Application Support/MenuBoard/Clipboard/`.
- **Keys** – simple system-wide key remaps (Caps Lock → Control, Caps Lock → Escape, swap ` and §, F-keys,
  arrows…) applied through `hidutil`, the mechanism behind Karabiner's "simple modifications". No driver and no
  Accessibility permission. Remaps persist until logout and are re-applied at launch.
  A **hyper key** (hold one modifier for ⌃⌥⇧⌘, optionally Escape when tapped alone) is available too; it uses a
  CGEvent tap and therefore needs the Accessibility permission. No layers or per-app rules; use Karabiner-Elements
  for those.

## Shelf details

- **Files** are referenced in place, never copied.
- **Browser images** arrive either as a file promise (received directly) or as the image URL, which is downloaded.
  Downloads land in `~/Library/Application Support/MenuBoard/Shelf/` and are deleted when you remove the item.
- **Links** are checked with a HEAD request: assets (image, video, PDF, zip…) are downloaded, pages stay as links.
- The drop zone appears for drags that carry a URL, file, image or file promise; plain text drags are ignored.
  Detection relies on a global mouse monitor plus the drag pasteboard's change count (no Accessibility permission needed).

## Build & run

```sh
make run        # swift build + wrap into build/MenuBoard.app + sign + launch
make install    # copy to /Applications
```

Requires macOS 15+ and Xcode 26. `swift build` alone produces a bare binary; use the script, because the
audio-capture permission is granted to a *bundle* and the usage description lives in `Resources/Info.plist`.
The script signs with your first "Apple Development" / "Developer ID" identity (override with `SIGN_IDENTITY=...`),
which keeps the permission grant stable across rebuilds. Ad-hoc signing works but re-prompts after every build.

Open the folder in Xcode (`xed .`) if you prefer an IDE; it is a plain Swift package.

## How per-app volume works

macOS has no public per-app volume API. MenuBoard uses Core Audio **process taps** (macOS 14.2+):
when you lower an app's slider it creates a tap on that app's processes with `mutedWhenTapped`, which silences the
app's own output, and replays the tapped audio through a private aggregate device on the current output at the chosen
gain. Moving the slider back to 100% destroys the tap and the app plays natively again.

Consequences:

- The first time you lower a slider macOS asks for **System Audio Recording** permission
  (System Settings → Privacy & Security → Screen & System Audio Recording). Without it the tap produces silence.
- Volumes are enforced only while MenuBoard is running; quitting it restores every app.
- Per-app volumes persist by bundle ID and are re-applied when the app next plays audio.
- Changing the default output device re-creates the taps on the new device.

## License

MIT, see `LICENSE`.

## Layout

```
Sources/MenuBoard/
  App/        NSApplication entry, status item, popover, drop overlay on the status button
  System/     CPU / memory / disk / battery sampling
  Processes/  per-app memory footprint (proc_pid_rusage, grouped by responsible pid)
  Audio/      Core Audio helpers, process taps, mixer state
  Shelf/      shelf model + persistence
  Views/      SwiftUI tabs
Resources/Info.plist
scripts/      build-app.sh, run.sh
```
