# Publishes a new version: builds the signed Windows installer on this pc and creates the GitHub release with it.
# GitHub Actions (.github/workflows/release.yml) then adds the Mac build and submits the version to winget.
#
#   powershell -ExecutionPolicy Bypass -File release.ps1           # check, build, sign, tag and publish
#   powershell -ExecutionPolicy Bypass -File release.ps1 -DryRun   # check and build only
#
# Signing happens here because the private key is in Certum SimplySign: connect SimplySign Desktop first.
# Needs the GitHub CLI, signed in (gh auth login), and a clean main that matches origin.
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. "$root\packaging\signing.ps1"

function Invoke-Git { git -C $root @args; if ($LASTEXITCODE -ne 0) { throw "git $args failed" } }

# --- Checks before building anything

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI not found. Install it with: winget install GitHub.cli, then run: gh auth login' }
    gh auth status *> $null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI is not signed in. Run: gh auth login' }
}

$version = ([xml](Get-Content "$root\src\Pastebird\Pastebird.csproj")).Project.PropertyGroup.Version | Where-Object { $_ } | Select-Object -First 1
$tag = "v$version"

$branch = git -C $root rev-parse --abbrev-ref HEAD
if ($branch -ne 'main') { throw "Not on main (on $branch)." }
if (git -C $root status --porcelain) { throw 'The working tree has uncommitted changes.' }
Invoke-Git fetch origin main --tags --quiet
if ((git -C $root rev-parse HEAD) -ne (git -C $root rev-parse origin/main)) { throw 'main differs from origin/main: push or pull first.' }
if (git -C $root tag --list $tag) { throw "Tag $tag already exists. Bump <Version> in Pastebird.csproj." }

# The section "## [<version>] - <date>" up to the next "## [" heading, followed by the install instructions.
$changelog = Get-Content "$root\CHANGELOG.md" -Raw
$match = [regex]::Match($changelog, '(?ms)^## \[' + [regex]::Escape($version) + '\][^\n]*\n(.*?)(?=^## \[|\z)')
if (-not $match.Success -or -not $match.Groups[1].Value.Trim()) { throw "CHANGELOG.md has no section for $version. Add '## [$version] - <date>' with the changes." }
$notes = $match.Groups[1].Value.Trim() + "`n`n---`n`n" + (Get-Content "$root\.github\release-notes.md" -Raw)

if (-not (Get-SigningConfig)) { throw 'No code signing certificate configured (packaging\signing.json). A release must be signed.' }

# --- Build and verify

& "$root\installer\build-installer.ps1"
$installer = "$root\publish\PastebirdSetup-$version.exe"
foreach ($file in "$root\publish\standalone\Pastebird.exe", $installer) {
    $signature = Get-AuthenticodeSignature $file
    if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw "$(Split-Path $file -Leaf) is not properly signed: $($signature.StatusMessage)" }
}

if ($DryRun) {
    Write-Host "Dry run: $installer is built and signed. Nothing was tagged or published."
    exit 0
}

# --- Tag and publish

Invoke-Git tag -a $tag -m "Pastebird $version"
Invoke-Git push origin $tag
$notesFile = Join-Path $env:TEMP 'pastebird-release-notes.md'
[IO.File]::WriteAllText($notesFile, $notes) # UTF-8 without BOM, also in Windows PowerShell 5.1
gh release create $tag $installer --repo pspeters/pastebird --verify-tag --title "Pastebird $version" --notes-file $notesFile
if ($LASTEXITCODE -ne 0) { throw "Creating the release failed. The tag $tag is pushed: run gh release create again, or delete the tag." }

Write-Host "Released Pastebird $version. GitHub Actions now adds the Mac build and submits to winget:"
Write-Host "  https://github.com/pspeters/pastebird/actions/workflows/release.yml"
