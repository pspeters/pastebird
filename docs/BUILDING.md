# Building Pastebird

Notes for developers and maintainers. Users only need the installer from the [Releases](https://github.com/pspeters/pastebird/releases) page.

## Building

Requires the .NET 10 SDK on Windows.

```bash
dotnet build src/Pastebird -c Release
```

To publish a single `Pastebird.exe`, which requires the [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0):

```bash
dotnet publish src/Pastebird -p:PublishProfile=win-x64
```

The output goes to `publish\Pastebird.exe`.

### Installer

Requires [Inno Setup 6](https://jrsoftware.org/isdl.php).

```bash
powershell -ExecutionPolicy Bypass -File installer/build-installer.ps1
```

This creates `publish\PastebirdSetup-<version>.exe` (about 42 MB). It includes .NET, so the target pc needs no runtime.

- Installs per user in `%LOCALAPPDATA%\Programs\Pastebird`, without admin rights.
- Adds a Start menu shortcut and starts Pastebird right after installation.
- A newer installer updates a running Pastebird in place.
- Uninstalling (Settings → Apps) also removes autostart and the stored history.
- The version number comes from `<Version>` in `Pastebird.csproj`.
- A silent install (`/VERYSILENT`) starts Pastebird afterwards. The built-in updater (`Services/UpdateService.cs`) relies on this: it downloads `PastebirdSetup-*.exe` from the latest GitHub release, verifies its size and SHA-256 digest, runs it silently and exits.

### Releasing

1. Bump `<Version>` in `Pastebird.csproj`.
2. Add a section for the new version at the top of [CHANGELOG.md](../CHANGELOG.md): `## [1.2.0] - 2026-11-01` followed by `### Added`, `### Changed`, `### Fixed` or `### Removed` with one line per change.
3. Commit and push a tag `v<version>` (for example `v1.2.0`).

The GitHub Actions workflow `.github/workflows/release.yml` builds the installer on Windows and publishes the release, with that changelog section as release notes. It stops when the tag doesn't match `<Version>` or the changelog has no section for it. With the `WINGET_TOKEN` secret it then also submits the new version to winget; see [packaging/winget](../packaging/winget/README.md). The changelog page on pastebird.app reads `CHANGELOG.md` from `main` and shows the versions up to the latest release, and installed copies of Pastebird pick up the update within a day.

### Code signing (OV certificate)

Without a signature, Windows shows "Unknown publisher". With an OV certificate, `build-installer.ps1` signs three files, each with a timestamp: `Pastebird.exe`, the installer and the uninstaller.

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

Without `signing.json` the script builds an unsigned installer and prints a warning. You can also pass the thumbprint via `$env:PASTEBIRD_CERT_THUMBPRINT`, which is handy in CI.

`build-msix.ps1 -Sign` signs the MSIX package for distribution outside the Store. For that, `Publisher` in `store-identity.json` must match the certificate subject.

Even signed builds may trigger SmartScreen for a new certificate until enough people have downloaded them and the certificate has built up reputation. Keep using the same certificate.

### Microsoft Store (MSIX)

```bash
powershell -ExecutionPolicy Bypass -File packaging/build-msix.ps1
```

This creates `publish\Pastebird_<version>.0_x64.msix` (about 60 MB). The tools (`makeappx`, `makepri`, `signtool`) come from the NuGet package `Microsoft.Windows.SDK.BuildTools`, so you don't need to install the Windows SDK.

The Store build (`-p:PastebirdMsix=true`) differs in one way: autostart uses the package's `StartupTask` instead of the registry. Users can turn it off in Pastebird or in Task Manager → Startup apps. In a Store install, history and settings are removed automatically on uninstall.

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
8. Bump `<Version>` in `Pastebird.csproj` for every update.

**Testing locally before upload**

- **Option A:** turn on Developer Mode (Settings → System → For developers), then run:
  `Add-AppxPackage -Register publish\msix-build\layout\AppxManifest.xml`
- **Option B:** build with `-TestCert`. The script prints the one-time command to trust the test certificate, which needs admin rights. Then double-click the `.msix` file.

To regenerate the icon and Store assets:

```bash
dotnet run --project tools/IconGen -- src/Pastebird/Assets packaging/msix/Assets
```

Set `ICON_PREVIEW=docs\logo.png` first to refresh the logo shown at the top of the README.

## Design and structure

C# / .NET 10 / WPF, with no NuGet dependencies.

```
src/Pastebird/
  App.xaml(.cs)              startup, single instance, wires the services together
  Core/
    ClipItem.cs              data model (id, content, type, copied at, last used)
    ClipboardHistory.cs      history: de-duplication, size limit, remove/clear
    FuzzySearch.cs           realtime search (substring > subsequence, then recency)
    Localization.cs          English and Dutch UI strings, switchable at runtime
    AppSettings.cs, Hotkey.cs, AppInfo.cs
    LocalStorage.cs          JSON + DPAPI in %LOCALAPPDATA%\Pastebird, written atomically
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

Why WPF and not WinUI 3: WinUI 3 has no API for tray icons or global hotkeys, so it would need Win32 interop anyway, on top of the Windows App SDK runtime and a slower startup. WPF gives the same native integration with fewer layers. The popup uses the real Windows 11 system backdrop through DWM. Pastebird renders in software mode: for such a small UI it is just as fast, and it roughly halves memory use (about 55 MB instead of 120 MB).