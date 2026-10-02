# Shared helpers for the build scripts: Windows SDK tools and Authenticode signing with an OV certificate.
#
# The certificate is found by thumbprint in the Windows certificate store (CurrentUser\My). That covers
# USB tokens (SafeNet/YubiKey) and cloud HSMs that present a virtual smart card (e.g. Certum SimplySign).
# Configure it in packaging\signing.json (see signing.example.json) or with $env:PASTEBIRD_CERT_THUMBPRINT.

function Get-SdkToolDir {
    # makeappx, makepri and signtool from NuGet (Microsoft.Windows.SDK.BuildTools); no Windows SDK install needed.
    dotnet restore "$PSScriptRoot\tools\BuildTools.csproj" -nologo -v q
    if ($LASTEXITCODE -ne 0) { throw 'Restoring Microsoft.Windows.SDK.BuildTools failed' }
    $packages = if ($env:NUGET_PACKAGES) { $env:NUGET_PACKAGES } else { "$env:USERPROFILE\.nuget\packages" }
    $signtool = Get-ChildItem "$packages\microsoft.windows.sdk.buildtools" -Recurse -Filter signtool.exe |
        Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1
    if (-not $signtool) { throw 'Windows SDK build tools not found' }
    return $signtool.DirectoryName
}

# Returns @{ Thumbprint; TimestampUrl; Subject } or $null when no certificate is configured (unsigned build).
function Get-SigningConfig {
    $config = $null
    $file = Join-Path $PSScriptRoot 'signing.json'
    if (Test-Path $file) { $config = Get-Content $file -Raw | ConvertFrom-Json }

    $thumbprint = if ($env:PASTEBIRD_CERT_THUMBPRINT) { $env:PASTEBIRD_CERT_THUMBPRINT } elseif ($config) { $config.Thumbprint } else { $null }
    if (-not $thumbprint) { return $null }
    $thumbprint = ($thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()

    $timestamp = if ($env:PASTEBIRD_TIMESTAMP_URL) { $env:PASTEBIRD_TIMESTAMP_URL }
                 elseif ($config -and $config.TimestampUrl) { $config.TimestampUrl }
                 else { 'http://timestamp.digicert.com' }

    $cert = Get-Item "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue
    if (-not $cert) { throw "Certificate $thumbprint not found in CurrentUser\My. Is the token connected / SimplySign logged in?" }
    if ($cert.NotAfter -lt (Get-Date)) { throw "Certificate $thumbprint expired on $($cert.NotAfter.ToShortDateString())." }
    if (-not ($cert.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.3')) { throw "Certificate $thumbprint is not a code signing certificate." }

    return [pscustomobject]@{ Thumbprint = $thumbprint; TimestampUrl = $timestamp; Subject = $cert.Subject }
}

function Get-SignArguments($signing) {
    # SHA-256 file digest + RFC 3161 timestamp, so signatures stay valid after the certificate expires.
    return @('sign', '/fd', 'sha256', '/tr', $signing.TimestampUrl, '/td', 'sha256', '/sha1', $signing.Thumbprint, '/d', 'Pastebird')
}

function Invoke-Sign($toolDir, $signing, [string[]]$files) {
    $signArgs = Get-SignArguments $signing
    & "$toolDir\signtool.exe" @signArgs @files
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $files" }
}

function Test-Signature($toolDir, [string]$file) {
    $ErrorActionPreference = 'Continue' # signtool reports an untrusted chain on stderr; that is a warning here
    & "$toolDir\signtool.exe" verify /pa /q $file 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Host "  Signature OK: $(Split-Path $file -Leaf)" }
    else { Write-Warning "Signature present but not trusted on this pc (expected for a test certificate): $(Split-Path $file -Leaf)" }
}

# Inno Setup sign tool definition: Inno calls this for the installer and the uninstaller ($f = file).
function Get-InnoSignTool($toolDir, $signing) {
    $signArgs = (Get-SignArguments $signing) -join ' '
    return "`$q$toolDir\signtool.exe`$q $signArgs `$f"
}
