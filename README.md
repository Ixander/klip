# Klip — a clipboard manager for macOS

A lightweight menu bar app: it keeps your copy history, gives you fast search,
and pastes the selected entry into the app you were just using. Written in
Swift + SwiftUI with no dependencies. Inspired by
[Maccy](https://github.com/p0deje/Maccy); the code is original.

## Features

- History of text, images and copied files (200 entries by default)
- Two ways in: the last 12 copies straight from the status bar menu, and a
  full search panel on ⌘⇧V
- Global hot key **⌘⇧V** (configurable in Settings)
- Search: exact match plus fuzzy matching
- Pin the entries you keep reaching for: each pin gets a permanent letter
  (⌘A, ⌘S, ⌘D…) that never shifts as the history changes, Maccy style
- Auto-paste via ⌘V into the previous app (needs Accessibility), or copy only
  and paste yourself — see Behavior below
- Keeps the RTF flavour of a copy, so formatting survives a round trip, and can
  drop it on demand
- Deduplication: copying something again moves it back to the top
- Skips "confidential" clipboards (`org.nspasteboard.ConcealedType` and
  friends), so passwords from password managers never reach the history
- Launch at login (SMAppService)
- Update check against GitHub Releases every 48 hours — see below
- History lives in `~/Library/Application Support/Klip/`

## Installation

There are no prebuilt binaries — Klip is built from source. All you need is the
Swift toolchain (`xcode-select --install`); full Xcode is not required.

```bash
git clone https://github.com/Ixander/klip.git
cd klip
./build.sh --install   # builds, copies to /Applications and launches
```

Without `--install` the bundle is left at `build/Klip.app`.

The icon can be regenerated with
`swift Tools/makeicon.swift && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns`

## Behavior when picking an entry

Two independent switches in Settings → Behavior:

- **Paste automatically** — send ⌘V right after copying. Off means the entry
  only lands on the clipboard and you paste it whenever you like.
- **Paste without formatting** — drop the RTF flavour, so the target app styles
  the text itself. This happens during the copy, so it applies even when
  nothing is pasted.

Holding a modifier while picking overrides both for that one pick:

| Held | Result |
|---|---|
| ⌘ | copy item |
| ⌥ | copy and paste item |
| ⌥⇧ | copy, clear formatting, and paste item |

Modifiers apply to a mouse click and to ↩. They are ignored for the ⌘1…⌘9 and
⌘‹letter› accelerators, which already need ⌘ to be held to work at all.

## Updates

Klip has no self-updater. Every 48 hours it asks the GitHub Releases API
whether a newer version exists and, if so, adds an **Update available → x.y.z**
item to the status bar menu that opens the release page. Nothing is downloaded
and nothing is replaced, which is what keeps the app free of the code-signing
requirements a real self-updater would carry.

Updating is manual:

```bash
cd klip && git pull && ./build.sh --install
```

The check can be turned off in Settings → Updates, where you can also trigger
it on demand. The only thing sent is a plain unauthenticated GET to
`api.github.com`; no identifiers, no clipboard data.

## Keyboard shortcuts in the history panel

| Keys | Action |
|---|---|
| ⌘⇧V | open/close the search panel |
| ↑ / ↓ , PgUp / PgDn | move the selection |
| ↩ | paste the selected entry |
| ⌘1…⌘9 | paste entry by number — unpinned entries only |
| ⌘A, ⌘S, ⌘D… | paste a pinned entry by its letter |
| ⌘P or ⌥P | pin / unpin |
| ⌘⌫ | delete entry |
| ⌘, | Settings |
| ⎋ | close |

Typing any other character filters the list immediately.

Pinned entries form their own block at the top, separated from the rest, both
in the panel and in the status bar menu. Each keeps the letter it was given
until you unpin it, so a pin you have learned stays where you learned it —
unlike ⌘1…⌘9, which follow whatever you copied last. Letters are handed out in
the order `a s d f g h j k l ; w e r t y u i o z x c v b n m`; `p` and `q` are
skipped because ⌘P and ⌘Q are taken.

In the status bar menu the first 9 unpinned entries get ⌘1…⌘9 accelerators and
images show as thumbnails.

## Troubleshooting

The app writes an event log to `~/Library/Application Support/Klip/klip.log`
(hot key registration, activations, panel opens, items added — never clipboard
contents). Useful when something refuses to show up.

## Permissions

- **Accessibility** is needed only for auto-paste (the ⌘V emulation). Without
  it an entry is still copied to the clipboard and you paste it yourself.
  System Settings → Privacy & Security → Accessibility → add Klip.
- The global hot key works **without** Accessibility (Carbon
  `RegisterEventHotKey`).

## Known limitations

- **Ad-hoc signing and the Accessibility permission.** By default Klip is
  signed ad-hoc, and macOS ties a granted permission to the checksum of the
  binary. After a rebuild the checksum differs, so the old entry in the
  Accessibility list keeps its toggle switched on while no longer having any
  effect — auto-paste silently stops working. Reset the stale entry with:

  ```bash
  tccutil reset Accessibility io.github.ixander.klip
  ```

  then restart Klip and grant the permission again. If you install once and
  never rebuild, this never affects you. If you do rebuild often, see below.

- Images are stored as PNG in `~/Library/Application Support/Klip/images/`;
  large screenshots add up. Clearing the history deletes them.

## Signing, for people who develop Klip

To stop the Accessibility permission from breaking on every rebuild, sign the
app with your own certificate instead of ad-hoc. `build.sh` picks it up
automatically: if the keychain holds a code-signing certificate named
**Klip Dev** it signs with that, otherwise it quietly falls back to ad-hoc.
Use `KLIP_SIGN_IDENTITY` to point at a different name.

Create the certificate once through **Keychain Access → Certificate Assistant →
Create a Certificate…**: name `Klip Dev`, Identity Type *Self Signed Root*,
Certificate Type *Code Signing*. Then:

```bash
./build.sh --install
tccutil reset Accessibility io.github.ixander.klip
```

Grant the permission one last time — from then on it survives rebuilds, because
the designated requirement is pinned to the certificate rather than to the
contents of the binary.

The certificate stays on your machine and never enters the repository. Giving
*users* permissions that survive updates requires an Apple Developer ID
($99/year); a self-signed certificate cannot do that.

## Source layout

| File | Purpose |
|---|---|
| `main.swift` | entry point, `.accessory` mode (no Dock icon) |
| `AppDelegate.swift` | wiring, status bar menu |
| `ClipboardMonitor.swift` | polls `NSPasteboard` every 0.3 s, filters types |
| `HistoryStore.swift` | history model, dedup, trimming, JSON persistence |
| `ClipItem.swift` | one history entry (text / image / files) |
| `HistoryPanelController.swift` | `NSPanel`, key interception, auto-paste |
| `HistoryPanelModel.swift` | search, filtering, selection, key handling |
| `HistoryView.swift` | SwiftUI list interface |
| `HotKey.swift` | global hot key via Carbon |
| `Paster.swift` | pick behavior, ⌘V emulation via CGEvent, Accessibility check |
| `UpdateChecker.swift` | GitHub Releases version check, no downloading |
| `SettingsView.swift`, `HotKeyRecorderView.swift` | settings, shortcut recorder |

## License

[MIT](LICENSE) © 2026 Oleksandr Kyrylov
