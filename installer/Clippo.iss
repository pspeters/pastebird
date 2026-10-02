; Clippo installer (Inno Setup 6). Build with: powershell -File installer\build-installer.ps1

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{6A0F3C2E-7D51-4B8E-9C3A-21F4E8B0D7A9}
AppName=Clippo
AppVersion={#AppVersion}
AppVerName=Clippo {#AppVersion}
AppPublisher=Clippo
VersionInfoVersion={#AppVersion}
; Per-user install in %LOCALAPPDATA%\Programs\Clippo: no administrator rights needed.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Clippo
DefaultGroupName=Clippo
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
OutputDir=..\publish
OutputBaseFilename=ClippoSetup-{#AppVersion}
SetupIconFile=..\src\Clippo\Assets\clippo.ico
UninstallDisplayIcon={app}\Clippo.exe
UninstallDisplayName=Clippo
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
#ifdef Sign
; "clipposign" is passed in by build-installer.ps1 (/S switch) and signs setup + uninstaller.
SignTool=clipposign
SignedUninstaller=yes
#endif

[Languages]
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"

[Files]
Source: "..\publish\standalone\Clippo.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Clippo"; Filename: "{app}\Clippo.exe"

[Registry]
; Clippo writes its own autostart entry; make sure uninstalling removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Clippo"; ValueType: none; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Clippo.exe"; Description: "Clippo nu starten"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clipboard history and settings
Type: filesandordirs; Name: "{localappdata}\Clippo"

[Code]
procedure StopClippo();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im Clippo.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopClippo(); // allow updating while Clippo runs in the tray
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopClippo();
  Result := True;
end;
