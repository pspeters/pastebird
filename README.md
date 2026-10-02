<p align="center"><img src="docs/logo.png" width="112" alt="Pastebird logo"></p>

# Pastebird

A dead-simple, fast clipboard manager for Windows 10 and 11.

**Ctrl+C → later Ctrl+Shift+V → type → Enter → done.**

Pastebird runs quietly in the system tray and remembers what you copy: text, URLs, file paths and copied files. One shortcut opens a small popup where you search and paste.

- No main window, no toolbar, no clutter.
- Keyboard-first: everything works without a mouse.
- Native Windows 11 look with acrylic, rounded corners and light/dark mode.
- 100% local: no account, no cloud, no telemetry, no network access.
- Available in English and Dutch.

## Download

Get the latest installer (`PastebirdSetup-<version>.exe`) from the [Releases](https://github.com/pspeters/pastebird/releases/latest) page and run it.

- Works on Windows 10 and 11. No admin rights and no extra software needed.
- Pastebird starts right after installation and lives in the system tray (bottom right, next to the clock).
- Uninstall through Settings → Apps. This also removes your stored history.

## Usage

| Key | Action |
|---|---|
| `Ctrl + Shift + V` | Open Pastebird (press again to close) |
| type | Fuzzy search (`proj` finds `C:\Projects\website\index.php`) |
| `↑` / `↓`, `PgUp` / `PgDn` | Navigate |
| `Enter` | Put the item on the clipboard and paste it into the previous window |
| `Shift + Enter` | Copy only, don't paste |
| `Delete` | Remove the selected item (when the cursor is at the end of the search box) |
| `Ctrl + Delete` | Clear the entire history |
| `Esc` | Close |

- **Click the tray icon** to open the popup next to the icon. **Right-click** for Open Pastebird · Clear history · Settings · Exit.
- Copying or choosing an item again moves it to the top. Pastebird never stores duplicates.
- Copied files are restored as real files, so pasting in Explorer works, and also as text (the path).

## Settings

Pastebird works out of the box, so you shouldn't need Settings. They cover:

- **Start with Windows** (on by default)
- **Paste automatically** (on by default)
- **Shortcut** (default `Ctrl + Shift + V`)
- **History size**: 50, 100, 200 or 500 items (default 200)
- **Language**: system default, English or Dutch
- **Clear history**

## Good to know

- **Ctrl+Shift+V in other apps.** In some programs (Chrome, Word, Teams) `Ctrl+Shift+V` means "paste without formatting". Pastebird takes over this shortcut system-wide. You can choose a different shortcut in Settings.
- **Automatic paste.** After you press Enter, Pastebird pastes into the window you were working in. Windows doesn't allow this in programs running as administrator. There the item is still on the clipboard, so just press `Ctrl+V`.

## Privacy

- Everything stays in `%LOCALAPPDATA%\Pastebird` on your pc: no network, accounts, telemetry or cloud.
- Your history is encrypted for your Windows user account. Other accounts and other pcs can't read it.
- Content that password managers mark as private is never stored.
- Very large items (over 200,000 characters) are skipped, and the history size is capped.

## Support

Pastebird is free and open source. If it saves you time, you can [buy me a coffee](https://buymeacoffee.com/PatrickS86) ☕

Found a bug or have an idea? [Open an issue](https://github.com/pspeters/pastebird/issues).

## License

MIT, see [LICENSE](LICENSE). Created by Patrick Speters.

<sub>Building from source: see [docs/BUILDING.md](docs/BUILDING.md).</sub>
