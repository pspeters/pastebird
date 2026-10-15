# Translating Pastebird

Pastebird is available in English and Dutch. You can add your language. No programming is needed: you translate one text file.

## The language files

Each language is one file in [`src/Pastebird/Languages`](../src/Pastebird/Languages):

| File | Language |
| --- | --- |
| `en.json` | English (the source; every other language falls back to it) |
| `nl.json` | Dutch |

The file name is the language code: `de.json` for German, `fr.json` for French, `pt-BR.json` for Brazilian Portuguese, and so on.

A file looks like this:

```json
{
  "language.name": "Deutsch",

  "popup.search": "Zwischenablage durchsuchen…",
  "popup.copied.minutes": "Vor {0} Min. kopiert",
  ...
}
```

The left side is the key. Keep it as it is. Translate only the right side.

## How to translate

1. Copy `en.json` and name the copy after your language, e.g. `de.json`.
2. Set `language.name` to the name of your language in your language: `Deutsch`, `Français`, `Español`.
3. Translate the texts. Keep these as they are:
   - **Placeholders** such as `{0}`, `{1}` and `{0:N0}`. Pastebird fills them in, for example with a version number or a shortcut. You can move them in the sentence.
   - **`\n`**: a new line.
   - **Key names** such as `Ctrl+Enter`, `Delete` and `Shift`, unless your keyboard labels them differently.
   - **`⁠`**: an invisible character that keeps `Shift+Enter` on one line.
4. `whatsnew.english` is shown above the list of changes, which is only written in English. In English it is empty. In your language, write something like "The changes are described in English."
5. If you're not sure about a text, leave the English text. Pastebird uses English for every text that is missing.

Write the way Windows does in your language: short, friendly and informal where Windows is. Look at the Windows Settings app for the words it uses, such as *taskbar*, *clipboard* and *Task Manager*.

## Try your translation

You don't need to build Pastebird to see your translation:

1. Put your file in `%LOCALAPPDATA%\Pastebird\Languages` (paste this path in the address bar of File Explorer and create the `Languages` folder).
2. Exit Pastebird (right-click the tray icon → **Exit**) and start it again.
3. Choose your language in **Settings → Language**.

A file in that folder also overrides texts of a built-in language, so you can use it to improve an existing translation.

If you use the Microsoft Store version and your language doesn't show up, try it with the installer version from GitHub.

## Send it in

- Open a pull request that adds your file to `src/Pastebird/Languages`, or
- [open an issue](https://github.com/pspeters/pastebird/issues/new) and attach your file.

When new texts are added to Pastebird, they appear in English until someone translates them. The changes in each release show which texts are new.

## For maintainers

- Every `*.json` file in `src/Pastebird/Languages` is built into Pastebird and appears in **Settings → Language** automatically.
- Add new texts to `en.json` first. Other files may lag behind; the English text is shown for missing keys.
- For the Microsoft Store listing in a new language, add a `<Resource Language="…" />` to `packaging/msix/AppxManifest.xml` and the texts to `packaging/msix/store-listing.md`.
