# Changelog

What's new in each version of Pastebird. The newest version is at the top.

<!--
For every release, add a section at the top in this format before you push the tag:

## [x.y.z] - YYYY-MM-DD

### Added / ### Changed / ### Fixed / ### Removed
- One line per change, written for users.

The release workflow copies this section into the GitHub release and stops when it is missing.
The website (pastebird.app/changelog.php) shows this file from the main branch, up to the latest released version.
-->

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
