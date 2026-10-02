# Builds publish\Clippo_<version>_x64.msix for the Microsoft Store.
#
#   powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1            # unsigned: for Store upload (the Store signs it)
#   powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1 -TestCert  # signed with a local test certificate, for sideloading
#   powershell -ExecutionPolicy Bypass -File packaging\build-msix.ps1 -Sign      # signed with your OV certificate (packaging\signing.json),
#                                                                                 # for distribution outside the Store; Publisher must equal the certificate subject
#
# Fill in packaging\msix\store-identity.json with the values from Partner Center first
# (Product > Product identity: Package/Identity/Name, Package/Identity/Publisher, Package/Properties/PublisherDisplayName).
param([switch]$TestCert, [switch]$Sign)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. "$PSScriptRoot\signing.ps1"

$identity = Get-Content "$PSScriptRoot\msix\store-identity.json" -Raw | ConvertFrom-Json
$version = ([xml](Get-Content "$root\src\Clippo\Clippo.csproj")).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
$msixVersion = "$version.0" # the Store requires the fourth number to be 0

# --- Packaging tools (NuGet: Microsoft.Windows.SDK.BuildTools)
$toolDir = Get-SdkToolDir
$makeappx = Get-Item "$toolDir\makeappx.exe"

if ($Sign) {
    $signing = Get-SigningConfig
    if (-not $signing) { throw 'No certificate configured in packaging\signing.json.' }
    if ($signing.Subject -ne $identity.Publisher) { throw "store-identity.json Publisher must equal the certificate subject: $($signing.Subject)" }
}

# --- Layout (inside the repo: some security software blocks reading new .exe files in %TEMP%)
$work = Join-Path $root 'publish\msix-build'
$layout = Join-Path $work 'layout'
$priRoot = Join-Path $work 'pri'
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

dotnet publish "$root\src\Clippo" -c Release -r win-x64 --self-contained true -p:ClippoMsix=true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -p:DebugType=none -o $layout -nologo -v q
if ($LASTEXITCODE -ne 0) { throw 'dotnet publish failed' }

$manifest = (Get-Content "$PSScriptRoot\msix\AppxManifest.xml" -Raw).
    Replace('$IdentityName$', $identity.IdentityName).
    Replace('$Publisher$', $identity.Publisher).
    Replace('$PublisherDisplayName$', $identity.PublisherDisplayName).
    Replace('$Version$', $msixVersion)
Copy-Item "$PSScriptRoot\msix\Assets" "$layout\Assets" -Recurse
Set-Content "$layout\AppxManifest.xml" $manifest -Encoding UTF8

# --- resources.pri: lets Windows pick the right icon size (scale-200, targetsize-24, ...)
New-Item -ItemType Directory $priRoot | Out-Null
Copy-Item "$PSScriptRoot\msix\Assets" "$priRoot\Assets" -Recurse
Copy-Item "$layout\AppxManifest.xml" $priRoot
& "$toolDir\makepri.exe" createconfig /cf "$work\priconfig.xml" /dq en-US_nl-NL /pv 10.0.0 /o | Out-Null
# One resources.pri for all scales (no split resource packs; those are only for bundles).
$priConfig = [xml](Get-Content "$work\priconfig.xml")
$priConfig.resources.packaging | ForEach-Object { [void]$_.ParentNode.RemoveChild($_) }
$priConfig.Save("$work\priconfig.xml")
& "$toolDir\makepri.exe" new /pr $priRoot /cf "$work\priconfig.xml" /of "$layout\resources.pri" /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makepri failed' }

# --- Pack
$msix = Join-Path $work "Clippo_${msixVersion}_x64.msix"
& $makeappx.FullName pack /d $layout /p $msix /o | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'makeappx failed (run it manually without | Out-Null to see why)' }

if ($TestCert) {
    # Self-signed certificate whose subject matches the manifest Publisher (kept in your user store).
    $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq $identity.Publisher } | Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -Type Custom -Subject $identity.Publisher -KeyUsage DigitalSignature `
            -FriendlyName 'Clippo test signing' -CertStoreLocation Cert:\CurrentUser\My `
            -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
    }
    & "$toolDir\signtool.exe" sign /fd SHA256 /sha1 $cert.Thumbprint /s My $msix | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'signtool failed' }
    Export-Certificate -Cert $cert -FilePath "$root\publish\Clippo-test.cer" | Out-Null
    Write-Host "Signed with test certificate. To trust it once (as administrator):"
    Write-Host "  Import-Certificate -FilePath `"$root\publish\Clippo-test.cer`" -CertStoreLocation Cert:\LocalMachine\TrustedPeople"
}

if ($Sign) {
    Invoke-Sign $toolDir $signing $msix
    Test-Signature $toolDir $msix
}

New-Item -ItemType Directory -Force "$root\publish" | Out-Null
Copy-Item $msix "$root\publish\" -Force
Write-Host "MSIX: $root\publish\Clippo_${msixVersion}_x64.msix"
