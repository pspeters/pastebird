# Clippo

Een extreem eenvoudige, snelle clipboard manager voor Windows 10/11.

**Ctrl+C → later Ctrl+Shift+V → typen → Enter → klaar.**

Clippo draait stil in het systeemvak, onthoudt wat je kopieert (tekst, URL's, paden en gekopieerde bestanden) en opent met één sneltoets een kleine popup om te zoeken en te plakken.

## Gebruik

| Toets | Actie |
|---|---|
| `Ctrl + Shift + V` | Clippo openen (nogmaals: sluiten) |
| typen | fuzzy zoeken (`proj` vindt `C:\Projecten\website\index.php`) |
| `↑` / `↓`, `PgUp` / `PgDn` | navigeren |
| `Enter` | item op het klembord zetten en direct plakken in het vorige venster |
| `Shift + Enter` | alleen kopiëren, niet plakken |
| `Delete` | geselecteerd item verwijderen (als de cursor aan het eind van het zoekveld staat) |
| `Ctrl + Delete` | volledige geschiedenis wissen |
| `Esc` | sluiten |

- **Klik op het tray-icoon**: popup bij het icoon. **Rechtsklik**: Open Clippo · Geschiedenis wissen · Instellingen · Afsluiten.
- Clippo nogmaals starten opent de popup van de draaiende instantie.
- Een item dat je opnieuw kopieert of kiest, komt bovenaan. Er ontstaan geen dubbele items.
- Gekopieerde bestanden worden teruggezet als echte bestanden (plakken in Verkenner werkt) en als tekst (het pad).

## Privacy

- Alles blijft lokaal in `%LOCALAPPDATA%\Clippo`: geen netwerk, accounts, telemetrie of cloud.
- `history.dat` is versleuteld met Windows DPAPI voor jouw gebruikersaccount. Andere accounts of andere pc's kunnen het niet lezen.
- Inhoud die wachtwoordmanagers als privé markeren (`ExcludeClipboardContentFromMonitorProcessing`, `CanIncludeInClipboardHistory = 0`) wordt niet opgeslagen.
- Items groter dan 200.000 tekens worden overgeslagen. De geschiedenis is begrensd (50/100/200/500, standaard 200).

## Bouwen

Vereist: .NET 10 SDK (Windows).

```bash
dotnet build src/Clippo -c Release
```

Eén los `Clippo.exe` (vereist de [.NET 10 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/10.0)):

```bash
dotnet publish src/Clippo -p:PublishProfile=win-x64
```

Het resultaat staat in `publish\Clippo.exe`. Voor een versie zonder runtime-vereiste voeg je `-p:SelfContained=true` toe (groter bestand, ca. 70 MB).

### Installer

Vereist: [Inno Setup 6](https://jrsoftware.org/isdl.php).

```bash
powershell -ExecutionPolicy Bypass -File installer/build-installer.ps1
```

Dit maakt `publish\ClippoSetup-<versie>.exe` (ca. 42 MB, inclusief .NET, dus geen runtime nodig op de doel-pc).

- Installatie per gebruiker in `%LOCALAPPDATA%\Programs\Clippo`, zonder adminrechten.
- Er komt een snelkoppeling in het startmenu en Clippo start direct na de installatie.
- Een nieuwere installer installeert over een draaiende Clippo heen.
- De-installeren (via Instellingen → Apps) verwijdert ook de autostart en de opgeslagen geschiedenis.
- Het versienummer komt uit `<Version>` in `Clippo.csproj`.

### Ondertekenen met een OV-certificaat

Zonder handtekening toont Windows "Onbekende uitgever". Met een OV-certificaat ondertekent `build-installer.ps1` automatisch drie bestanden, elk met een tijdstempel: `Clippo.exe`, de installer en de uninstaller.

1. Koop een OV-codesigning-certificaat, bijvoorbeeld bij Certum, Sectigo of SSL.com. De sleutel staat verplicht op een USB-token of in een cloud-HSM.
2. Installeer de software van de leverancier en sluit het token aan, of log in bij de cloud-HSM (zoals Certum SimplySign). Het certificaat staat dan in je Windows-certificaatarchief.
3. Zoek de thumbprint op:
   `Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject, Thumbprint, NotAfter`
4. Kopieer `packaging/signing.example.json` naar `packaging/signing.json` en vul de thumbprint in. Gebruik als `TimestampUrl` de tijdstempelserver van je leverancier:

   | Leverancier | Tijdstempelserver |
   |---|---|
   | Certum | `http://time.certum.pl` |
   | Sectigo | `http://timestamp.sectigo.com` |
   | SSL.com | `http://ts.ssl.com` |
   | DigiCert | `http://timestamp.digicert.com` |

5. Bouw zoals altijd met `installer/build-installer.ps1`. Bij een token vraagt Windows om je pincode.

Zonder `signing.json` bouwt het script gewoon onondertekend, met een waarschuwing. Je kunt de thumbprint ook meegeven via `$env:CLIPPO_CERT_THUMBPRINT` (handig in CI). Met `build-msix.ps1 -Sign` onderteken je het MSIX-pakket voor verspreiding buiten de Store. Daarvoor moet `Publisher` in `store-identity.json` gelijk zijn aan het onderwerp van het certificaat.

Let op: ook ondertekend kan SmartScreen bij een nieuw certificaat de eerste weken nog waarschuwen, totdat er genoeg downloads zijn geweest en het certificaat reputatie heeft opgebouwd. Gebruik dus steeds hetzelfde certificaat.

### Microsoft Store (MSIX)

```bash
powershell -ExecutionPolicy Bypass -File packaging/build-msix.ps1
```

Dit maakt `publish\Clippo_<versie>.0_x64.msix` (ca. 60 MB). De tools (`makeappx`, `makepri`, `signtool`) komen automatisch uit het NuGet-pakket `Microsoft.Windows.SDK.BuildTools`; een Windows SDK installeren is niet nodig.

De Store-build (`-p:ClippoMsix=true`) verschilt op één punt: autostart loopt via de `StartupTask` van het pakket in plaats van via de registry. Je kunt het uitzetten in Clippo of in Taakbeheer → Opstart-apps. Geschiedenis en instellingen worden in een Store-installatie automatisch verwijderd bij het de-installeren.

**Publiceren**

1. Maak een ontwikkelaarsaccount aan via [storedeveloper.microsoft.com](https://storedeveloper.microsoft.com).
2. Reserveer in Partner Center een productnaam. Is "Clippo" bezet, kies dan bijvoorbeeld "Clippo Clipboard".
3. Neem onder *Product identity* de waarden over in `packaging/msix/store-identity.json`:
   - `Package/Identity/Name` → `IdentityName`
   - `Package/Identity/Publisher` → `Publisher` (`CN=...`)
   - `Package/Properties/PublisherDisplayName` → `PublisherDisplayName`
4. Bouw het pakket en upload het `.msix`-bestand. Ondertekenen is niet nodig, want dat doet de Store.
5. Vul de Store-vermelding in:
   - beschrijving
   - minstens één screenshot
   - leeftijdsclassificatie
   - prijs (gratis)
   - URL van een privacybeleid
6. Partner Center vraagt een toelichting voor de capability `runFullTrust`. Bijvoorbeeld: *"Klassieke WPF-desktopapp die een systeemvakpictogram, een globale sneltoets en klembordmonitoring gebruikt. Alle gegevens blijven lokaal."*
7. De certificering duurt meestal enkele werkdagen. Updates gaan daarna automatisch naar gebruikers.
8. Voor elke update verhoog je `<Version>` in `Clippo.csproj`.

**Lokaal testen vóór upload**

- **Optie A:** zet Ontwikkelaarsmodus aan (Instellingen → Systeem → Voor ontwikkelaars). Daarna:
  `Add-AppxPackage -Register publish\msix-build\layout\AppxManifest.xml`
- **Optie B:** bouw met `-TestCert`. Het script geeft dan het eenmalige commando om het testcertificaat te vertrouwen; daarvoor zijn adminrechten nodig. Daarna dubbelklik je het `.msix`-bestand.

Icoon en Store-iconen opnieuw genereren:

```bash
dotnet run --project tools/IconGen -- src/Clippo/Assets packaging/msix/Assets
```

## Techniek en structuur

C# / .NET 10 / WPF, zonder NuGet-dependencies.

```
src/Clippo/
  App.xaml(.cs)              opstarten, single-instance, koppelt de services
  Core/
    ClipItem.cs              datamodel (id, inhoud, type, gekopieerd, laatst gebruikt)
    ClipboardHistory.cs      geschiedenis: dedupe, max. aantal, verwijderen/wissen
    FuzzySearch.cs           realtime zoeken (substring > subsequence, daarna recentheid)
    AppSettings.cs, Hotkey.cs
    LocalStorage.cs          JSON + DPAPI in %LOCALAPPDATA%\Clippo, atomisch weggeschreven
  Services/
    MessageWindow.cs         één verborgen Win32-venster voor alle systeemberichten
    ClipboardMonitor.cs      AddClipboardFormatListener, lezen/terugzetten
    GlobalHotkeyService.cs   RegisterHotKey
    TrayIconService.cs       Shell_NotifyIcon + native contextmenu
    PasteService.cs          vorig venster onthouden, Ctrl+V via SendInput
    SystemIntegration.cs     autostart (HKCU\...\Run), light/dark
  UI/
    PopupWindow.xaml(.cs)    de popup (DWM acrylic, afgeronde hoeken, schaduw)
    SettingsWindow.xaml(.cs) instellingen (WPF Fluent-thema)
tools/IconGen/               genereert Assets/clippo.ico
```

Waarom WPF in plaats van WinUI 3: WinUI 3 heeft geen API voor tray-iconen of globale sneltoetsen, dus daar is toch Win32-interop nodig. Daarbovenop komen de Windows App SDK-runtime en een tragere opstart. WPF geeft dezelfde native integratie met minder lagen. De popup gebruikt de echte Windows 11-systeemachtergrond via DWM. De app rendert in software-modus, omdat dat bij zo'n kleine UI even snel is en het geheugengebruik ongeveer halveert (circa 55 MB in plaats van 120 MB).

Automatisch plakken stuurt `Ctrl+V` naar het venster dat actief was vóór Clippo opende. Dat gebeurt alleen als dat venster weer actief is en er geen modifier-toetsen meer ingedrukt zijn. Anders blijft het item gewoon op het klembord staan. In vensters met administratorrechten blokkeert Windows dit; gebruik dan zelf `Ctrl+V`. Automatisch plakken kun je uitzetten in Instellingen.

Let op: `Ctrl+Shift+V` is in sommige programma's (Chrome, Word, Teams) "plakken zonder opmaak". Clippo neemt die combinatie systeembreed over. Kies in Instellingen een andere sneltoets als je dat liever niet hebt.

## Licentie

MIT - zie [LICENSE](LICENSE).

