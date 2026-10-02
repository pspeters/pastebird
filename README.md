# Clippo

A dead-simple, fast clipboard manager for Windows 10 and 11.

**Ctrl+C → later Ctrl+Shift+V → type → Enter → done.**

Clippo runs quietly in the system tray and remembers what you copy: text, URLs, file paths and copied files. One shortcut opens a small popup where you search and paste.

- No main window, no toolbar, no clutter.
- Keyboard-first: everything works without a mouse.
- Native Windows 11 look with acrylic, rounded corners and light/dark mode.
- 100% local: no account, no cloud, no telemetry, no network access.
- Available in English and Dutch.

## Usage

| Key | Action |
|---|---|
| `Ctrl + Shift + V` | Open Clippo (press again to close) |
| type | Fuzzy search (`proj` finds `C:\Projects\website\index.php`) |
| `↑` / `↓`, `PgUp` / `PgDn` | Navigate |
| `Enter` | Put the item on the clipboard and paste it into the previous window |
| `Shift + Enter` | Copy only, don't paste |
| `Delete` | Remove the selected item (when the cursor is at the end of the search box) |
| `Ctrl + Delete` | Clear the entire history |
| `Esc` | Close |

- **Click the tray icon** to open the popup next to the icon. **Right-click** for Open Clippo · Clear history · Settings · Exit.
- Starting Clippo again opens the popup of the running instance.
- Copying or choosing an item again moves it to the top. Clippo never stores duplicates.
- Copied files are restored as real files, so pasting in Explorer works, and also as text (the path).

## Settings

Clippo works out of the box, so you shouldn't need Settings. They cover:

- **Start with Windows** (on by default)
- **Paste automatically** (on by default)
- **Shortcut** (default `Ctrl + Shift + V`)
- **History size**: 50, 100, 200 or 500 items (default 200)
- **Language**: system default, English or Dutch
- **Clear history**

Settings also has an **About** section with the version, license and links to the source code and to [Buy me a coffee](https://buymeacoffee.com/pspeters).

## Privacy

- Everything stays in `%LOCALAPPDATA%\Clippo` on your pc: no network, accounts, telemetry or cloud.
- `history.dat` is encrypted with Windows DPAPI for your user account. Other accounts and other machines can't read it.
- Content that password managers mark as private (`ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory = 0`) is never stored.
- Items larger than 200,000 characters are skipped, and the history size is capped.

## Building

Requires the .NET 10 SDK on Windows.

```bash
dotnet build src/Clippo -c Release
```

To publish a single `Clippo.exe`, which requires the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0):

```bash
dotnet publish src/Clippo -p:PublishProfile=win-x64
```

The output goes to `publish\Clippo.exe`.

### Installer

Requires [Inno Setup 6](https://jrsoftware.org/isdl.php).

```bash
powershell -ExecutionPolicy Bypass -File installer/build-installer.ps1
```

This creates `publish\ClippoSetup-<version>.exe` (about 42 MB). It includes .NET, so the target pc needs no runtime.

- Installs per user in `%LOCALAPPDATA%\Programs\Clippo`, without admin rights.
- Adds a Start menu shortcut and starts Clippo right after installation.
- A newer installer updates a running Clippo in place.
- Uninstalling (Settings → Apps) also removes autostart and the stored history.
- The version number comes from `<Version>` in `Clippo.csproj`.

### Code signing (OV certificate)

Without a signature, Windows shows "Unknown publisher". With an OV certificate, `build-installer.ps1` signs three files, each with a timestamp: `Clippo.exe`, the installer and the uninstaller.

1. Buy an OV code signing certificate, for example from Certum, Sectigo or SSL.com. The private key must live on a USB token or in a cloud HSM.
2. Install the vendor's software and connect the token, or sign in to the cloud HSM (such as Certum SimplySign). The certificate then appears in your Windows certificate store.
3. Look up the thumbprint:
   `Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject, Thumbprint, NotAfter`
4. Copy `packaging/signing.example.json` to `packaging/signing.json` and fill in the thumbprint. Set `TimestampUrl` to your vendor's timestamp server:

   | Vendor | Timestamp server |
   |---|---|
   | Certum | `http://time.certum.pl` |
   | Sectigo | `http://timestamp.sectigo.com` |
   | SSL.com | `http://ts.ssl.com` |
   | DigiCert | `http://timestamp.digicert.com` |

5. Build as usual with `installer/build-installer.ps1`. With a token, Windows asks for your PIN.

Without `signing.json` the script builds an unsigned installer and prints a warning. You can also pass the thumbprint via `$env:CLIPPO_CERT_THUMBPRINT`, which is handy in CI.

`build-msix.ps1 -Sign` signs the MSIX package for distribution outside the Store. For that, `Publisher` in `store-identity.json` must match the certificate subject.

Even signed builds may trigger SmartScreen for a new certificate until enough people have downloaded them and the certificate has built up reputation. Keep using the same certificate.

### Microsoft Store (MSIX)

```bash
powershell -ExecutionPolicy Bypass -File packaging/build-msix.ps1
```

This creates `publish\Clippo_<version>.0_x64.msix` (about 60 MB). The tools (`makeappx`, `makepri`, `signtool`) come from the NuGet package `Microsoft.Windows.SDK.BuildTools`, so you don't need to install the Windows SDK.

The Store build (`-p:ClippoMsix=true`) differs in one way: autostart uses the package's `StartupTask` instead of the registry. Users can turn it off in Clippo or in Task Manager → Startup apps. In a Store install, history and settings are removed automatically on uninstall.

**Publishing**

1. Create a developer account at [storedeveloper.microsoft.com](https://storedeveloper.microsoft.com).
2. Reserve a product name in Partner Center.
3. Copy the values from *Product identity* into `packaging/msix/store-identity.json`:
   - `Package/Identity/Name` → `IdentityName`
   - `Package/Identity/Publisher` → `Publisher` (`CN=...`)
   - `Package/Properties/PublisherDisplayName` → `PublisherDisplayName`
4. Build the package and upload the `.msix` file. You don't need to sign it, because the Store does that.
5. Fill in the Store listing:
   - description
   - at least one screenshot
   - age rating
   - price (free)
   - privacy policy URL
6. Partner Center asks you to justify the `runFullTrust` capability. For example: *"Classic WPF desktop app that uses a tray icon, a global hotkey and clipboard monitoring. All data stays local."*
7. Certification usually takes a few business days. After that, updates reach users automatically.
8. Bump `<Version>` in `Clippo.csproj` for every update.

**Testing locally before upload**

- **Option A:** turn on Developer Mode (Settings → System → For developers), then run:
  `Add-AppxPackage -Register publish\msix-build\layout\AppxManifest.xml`
- **Option B:** build with `-TestCert`. The script prints the one-time command to trust the test certificate, which needs admin rights. Then double-click the `.msix` file.

To regenerate the icon and Store assets:

```bash
dotnet run --project tools/IconGen -- src/Clippo/Assets packaging/msix/Assets
```

## Design and structure

C# / .NET 10 / WPF, with no NuGet dependencies.

```
src/Clippo/
  App.xaml(.cs)              startup, single instance, wires the services together
  Core/
    ClipItem.cs              data model (id, content, type, copied at, last used)
    ClipboardHistory.cs      history: de-duplication, size limit, remove/clear
    FuzzySearch.cs           realtime search (substring > subsequence, then recency)
    Localization.cs          English and Dutch UI strings, switchable at runtime
    AppSettings.cs, Hotkey.cs, AppInfo.cs
    LocalStorage.cs          JSON + DPAPI in %LOCALAPPDATA%\Clippo, written atomically
  Services/
    MessageWindow.cs         one hidden Win32 window for all system messages
    ClipboardMonitor.cs      AddClipboardFormatListener, reading and restoring items
    GlobalHotkeyService.cs   RegisterHotKey
    TrayIconService.cs       Shell_NotifyIcon + native context menu
    PasteService.cs          remembers the previous window, sends Ctrl+V via SendInput
    SystemIntegration.cs     autostart (Run key or MSIX StartupTask), light/dark mode
  UI/
    PopupWindow.xaml(.cs)    the popup (DWM acrylic, rounded corners, shadow)
    SettingsWindow.xaml(.cs) settings and About (WPF Fluent theme)
installer/                   Inno Setup script and build script
packaging/                   MSIX manifest, Store assets, signing helpers
tools/IconGen/               generates the app icon and Store assets
```

Why WPF and not WinUI 3: WinUI 3 has no API for tray icons or global hotkeys, so it would need Win32 interop anyway, on top of the Windows App SDK runtime and a slower startup. WPF gives the same native integration with fewer layers. The popup uses the real Windows 11 system backdrop through DWM. Clippo renders in software mode: for such a small UI it is just as fast, and it roughly halves memory use (about 55 MB instead of 120 MB).

Automatic paste sends `Ctrl+V` to the window that was active before Clippo opened. It only does so when that window is active again and no modifier keys are held down. Otherwise the item simply stays on the clipboard. Windows blocks this for elevated (admin) windows; press `Ctrl+V` yourself there. You can turn automatic paste off in Settings.

Note: in some programs (Chrome, Word, Teams) `Ctrl+Shift+V` means "paste without formatting". Clippo takes over that shortcut system-wide. Pick a different shortcut in Settings if you prefer.

## Support

Clippo is free and open source. If it saves you time, you can [buy me a coffee](https://buymeacoffee.com/pspeters) ☕

## License

MIT, see [LICENSE](LICENSE). Created by Patrick Speters.
