; Pastebird installer (Inno Setup 6). Build with: powershell -File installer\build-installer.ps1

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
AppId={{23DB349F-5518-4A51-BF10-39BBB4178412}
AppName=Pastebird
AppVersion={#AppVersion}
AppVerName=Pastebird {#AppVersion}
AppPublisher=Pastebird
VersionInfoVersion={#AppVersion}
; Per-user install in %LOCALAPPDATA%\Programs\Pastebird: no administrator rights needed.
PrivilegesRequired=lowest
DefaultDirName={autopf}\Pastebird
DefaultGroupName=Pastebird
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
OutputDir=..\publish
OutputBaseFilename=PastebirdSetup-{#AppVersion}
SetupIconFile=..\src\Pastebird\Assets\pastebird.ico
UninstallDisplayIcon={app}\Pastebird.exe
UninstallDisplayName=Pastebird
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
#ifdef Sign
; "pastebirdsign" is passed in by build-installer.ps1 (/S switch) and signs setup + uninstaller.
SignTool=pastebirdsign
SignedUninstaller=yes
#endif

[Languages]
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"

[Files]
Source: "..\publish\standalone\Pastebird.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{userprograms}\Pastebird"; Filename: "{app}\Pastebird.exe"

[Registry]
; Pastebird writes its own autostart entry; make sure uninstalling removes it.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Pastebird"; ValueType: none; Flags: uninsdeletevalue

[Run]
Filename: "{app}\Pastebird.exe"; Description: "Pastebird nu starten"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Clipboard history and settings
Type: filesandordirs; Name: "{localappdata}\Pastebird"

[Code]
procedure StopPastebird();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/f /im Pastebird.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopPastebird(); // allow updating while Pastebird runs in the tray
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopPastebird();
  Result := True;
end;
