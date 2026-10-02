# Builds publish\ClippoSetup-<version>.exe: self-contained Clippo.exe wrapped in an Inno Setup installer.
# Signs Clippo.exe, the installer and the uninstaller when a code signing certificate is configured
# (packaging\signing.json or $env:CLIPPO_CERT_THUMBPRINT); otherwise builds unsigned.
param([switch]$Unsigned)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$root\packaging\signing.ps1"

$iscc = @(
    (Get-Command iscc -ErrorAction SilentlyContinue).Source,
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found. Install it from https://jrsoftware.org/isdl.php' }

$version = ([xml](Get-Content "$root\src\Clippo\Clippo.csproj")).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
$signing = if ($Unsigned) { $null } else { Get-SigningConfig }
if ($signing) {
    $toolDir = Get-SdkToolDir
    Write-Host "Signing with: $($signing.Subject)"
} else {
    Write-Warning 'No code signing certificate configured: building an UNSIGNED installer.'
}

dotnet publish "$root\src\Clippo" -p:PublishProfile=win-x64-standalone -nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

$isccArgs = @('/Q', "/DAppVersion=$version")
if ($signing) {
    Invoke-Sign $toolDir $signing "$root\publish\standalone\Clippo.exe"
    $isccArgs += '/DSign', "/Sclipposign=$(Get-InnoSignTool $toolDir $signing)"
}

# Compile outside OneDrive: syncing/antivirus can lock the file while Inno Setup writes it.
$out = Join-Path $env:TEMP "clippo-installer"
New-Item -ItemType Directory -Force $out | Out-Null
& $iscc @isccArgs "/O$out" "$root\installer\Clippo.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
Copy-Item "$out\ClippoSetup-$version.exe" "$root\publish\" -Force

if ($signing) {
    Test-Signature $toolDir "$root\publish\standalone\Clippo.exe"
    Test-Signature $toolDir "$root\publish\ClippoSetup-$version.exe"
}
Write-Host "Installer: $root\publish\ClippoSetup-$version.exe"
