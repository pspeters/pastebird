# Posts the CHANGELOG.md section of a version to X, with a campaign link to the changelog on the website.
# Needs X_API_KEY, X_API_SECRET, X_ACCESS_TOKEN and X_ACCESS_TOKEN_SECRET: an X app with Read and Write permissions,
# and the access token of the account that posts. -DryRun only prints the post.
param(
    [Parameter(Mandatory)][string]$Version,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$Version = $Version.TrimStart('v')

$maxWeight = 280
$urlWeight = 23  # X counts every link as 23 characters (t.co)

# Length as X counts it: most Latin text 1 per character, everything else (CJK, emoji) 2.
function Get-XWeight([string]$text) {
    $w = 0
    foreach ($c in $text.ToCharArray()) {
        if ([char]::IsLowSurrogate($c)) { continue }
        $n = [int]$c
        $w += if ($n -le 0x10FF -or ($n -ge 0x2000 -and $n -le 0x200D) -or ($n -ge 0x2010 -and $n -le 0x201F) -or ($n -ge 0x2032 -and $n -le 0x2037)) { 1 } else { 2 }
    }
    $w
}

# The "- item" lines of "## [<version>]" up to the next "## [" heading, as plain text.
$text = [regex]::Replace((Get-Content (Join-Path $PSScriptRoot '../CHANGELOG.md') -Raw), '(?s)<!--.*?-->', '')
$match = [regex]::Match($text, '(?ms)^## \[' + [regex]::Escape($Version) + '\][^\n]*\n(.*?)(?=^## \[|\z)')
if (-not $match.Success) { throw "CHANGELOG.md has no section for $Version" }
$items = [regex]::Matches($match.Groups[1].Value, '(?m)^[-*] (.+?)\s*$') | ForEach-Object {
    $item = [regex]::Replace($_.Groups[1].Value, '\[([^\]]+)\]\([^)]+\)', '$1')
    $item -replace '\*\*|__|`', ''
}

$link = "https://pastebird.app/changelog.php?lang=en&utm_source=x&utm_medium=social&utm_campaign=release-$Version"
$head = "Pastebird $Version is out:"
$more = '…and more'

# As many items as fit; the rest becomes "…and more".
$budget = $maxWeight - $urlWeight - (Get-XWeight $head) - 4  # the line breaks around the list
$lines = [System.Collections.Generic.List[string]]::new()
$used = 0
for ($i = 0; $i -lt @($items).Count; $i++) {
    $reserve = if ($i -lt @($items).Count - 1) { (Get-XWeight $more) + 1 } else { 0 }
    # The whole item, or else only its first sentence (not a question, which says little on its own).
    $candidates = @(('• ' + @($items)[$i]), ('• ' + [regex]::Match(@($items)[$i], '^[^?!]+?\.(?=\s|$)').Value))
    $line = $candidates | Where-Object { $_ -ne '• ' -and $used + (Get-XWeight $_) + 1 + $reserve -le $budget } | Select-Object -First 1
    if ($line) {
        $lines.Add($line)
        $used += (Get-XWeight $line) + 1
        continue
    }
    if ($lines.Count -eq 0) {
        # Even the first sentence of the first item is too long: cut it at a word.
        $cut = $candidates[0].Substring(0, $budget - (Get-XWeight $more) - 3)
        $lines.Add($cut.Substring(0, $cut.LastIndexOf(' ')).TrimEnd(',', ';', ':') + '…')
    }
    $lines.Add($more)
    break
}
$post = "$head`n`n" + ($lines -join "`n") + "`n`n$link"
$post
if ($DryRun) { return }

# OAuth 1.0a (HMAC-SHA1). With a JSON body only the oauth_ parameters are signed.
$url = 'https://api.x.com/2/tweets'
function Esc([string]$s) { [uri]::EscapeDataString($s) }
$oauth = [ordered]@{
    oauth_consumer_key = $env:X_API_KEY
    oauth_nonce = [guid]::NewGuid().ToString('N')
    oauth_signature_method = 'HMAC-SHA1'
    oauth_timestamp = [string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    oauth_token = $env:X_ACCESS_TOKEN
    oauth_version = '1.0'
}
$paramString = ($oauth.Keys | Sort-Object | ForEach-Object { "$(Esc $_)=$(Esc $oauth[$_])" }) -join '&'
$base = "POST&$(Esc $url)&$(Esc $paramString)"
$hmac = [System.Security.Cryptography.HMACSHA1]::new([Text.Encoding]::UTF8.GetBytes("$(Esc $env:X_API_SECRET)&$(Esc $env:X_ACCESS_TOKEN_SECRET)"))
$oauth.oauth_signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($base)))
$auth = 'OAuth ' + (($oauth.Keys | Sort-Object | ForEach-Object { "$(Esc $_)=`"$(Esc $oauth[$_])`"" }) -join ', ')

$body = [Text.Encoding]::UTF8.GetBytes((@{ text = $post } | ConvertTo-Json -Compress))
$response = Invoke-RestMethod -Method Post -Uri $url -Headers @{ Authorization = $auth } -ContentType 'application/json; charset=utf-8' -Body $body
"`nPosted: https://x.com/i/status/$($response.data.id)"
