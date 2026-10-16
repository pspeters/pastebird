# Changelog

What's new in each version of Pastebird. The newest version is at the top.

<!--
For every release, add a section at the top in this format before you run release.ps1:

## [x.y.z] - YYYY-MM-DD

### Added / ### Changed / ### Fixed / ### Removed
- One line per change, written for users.

release.ps1 copies this section into the GitHub release and stops when it is missing.
The website (pastebird.app/changelog.php) shows this file from the main branch, up to the latest released version.
-->

## [1.8.3] - 2026-10-16

### Added
- Settings tells you when Windows can't read text in images, and how to install that. As soon as it can, Pastebird reads your images, without a restart.

### Fixed
- Searching no longer shows long texts that merely contain the letters of your search somewhere, far apart.

## [1.8.2] - 2026-10-15

### Added
- Pastebird can be translated into more languages. Every language is one text file, shared by the Windows and the Mac version. Want to help? The guide is in docs/TRANSLATING.md on GitHub.

### Fixed
- **What's new** and Settings no longer open behind the Pastebird popup.
- Microsoft Store: after an update, Windows puts the Pastebird icon behind the arrow on the taskbar again. The update notification now says so, so you can drag it back.

## [1.8.1] - 2026-10-14

### Changed
- The Windows installer, the app and its uninstaller are now code-signed. Windows shows "Open Source Developer Patrick Speters" as the publisher instead of "Unknown publisher".

### Fixed
- Mac: the popup no longer shows a partly cut-off row at the bottom.

## [1.8.0] - 2026-10-13

### Added
- **Pastebird for Mac.** The same clipboard history, search, pins, preview and text recognition, on macOS 13 or later (Apple silicon and Intel). It lives in the menu bar: press **⇧⌘V**, type and press Return. On a Mac, ⌘ takes the place of Ctrl. Download the .dmg from the release or from pastebird.app.

## [1.7.2] - 2026-10-09

### Changed
- Updates are downloaded through pastebird.app, which only counts that an update happened: the old and the new version number, nothing else. The installer is still checked against the fingerprint GitHub publishes, and Pastebird downloads straight from GitHub if the website can't be reached.

## [1.7.1] - 2026-10-06

### Fixed
- The items in the popup are readable again in dark mode.
- The Microsoft Store version starts again by itself after the Store has updated it.

## [1.7.0] - 2026-10-06

### Added
- A trash icon appears when you hover over an item, so you can remove it with the mouse too.
- Removed something by mistake? Press **Ctrl+Z** in the popup to bring it back, also after Ctrl+Delete. This works until you close the popup.

## [1.6.0] - 2026-10-06

### Added
- **Search in screenshots:** Pastebird reads the text in copied images with the text recognition built into Windows, so typing a word finds the screenshot it is in. Press **Ctrl+Enter** on an image to paste its text. This works on your pc, without internet.
- **Remove old items** in Settings: let Pastebird remove items after 1, 7 or 30 days. Pinned items stay.

### Changed
- Pastebird keeps the 50 most recent images, so screenshots don't fill up your disk. Pinned images don't count.

## [1.5.0] - 2026-10-06

### Added
- Pastebird now remembers **images**, like screenshots (Win+Shift+S) and pictures copied in a browser. They show up with a small thumbnail; press Tab to see them larger.
- Text keeps its **formatting** (bold, links, tables) when you copied it from Word, Outlook or a web page. Press **Ctrl+Enter** to paste it as plain text.

## [1.4.0] - 2026-10-05

### Added
- Press **Tab** in the popup to see the full content of the selected item and when you copied it, handy for long or multi-line text. Press Tab again to hide it.
- Press **Ctrl+1** to **Ctrl+9** to paste the first to ninth item right away. Add Shift to copy it without pasting.

## [1.3.0] - 2026-10-04

### Added
- After an update, Pastebird lets you know it restarted on the new version. Click the notification to see what's new.
- **What's new** in Settings shows the changes of every version, also without an internet connection.

## [1.2.0] - 2026-10-04

### Added
- Pin items you use often, like a signature or an address: press **Ctrl+P** in the popup or click the pin icon that appears when you hover over an item. Pinned items stay at the top, don't count towards the history size and stay when you clear the history.

## [1.1.0] - 2026-10-04

### Added
- Pastebird checks for updates once a day. When a new version is available, a notification appears: click it to update. Pastebird downloads the new version from GitHub, checks it, installs it and restarts by itself. Your history and settings stay.
- Settings has a new **Check for updates automatically** option, with buttons to check now or update. You can turn the check off there.
