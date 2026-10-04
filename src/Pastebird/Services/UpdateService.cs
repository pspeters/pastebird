using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Windows.Threading;
using Pastebird.Core;

namespace Pastebird.Services;

public sealed record UpdateInfo(Version Version, string DownloadUrl, long Size, string? Sha256);

/// <summary>
/// Checks GitHub for a newer release (shortly after start, then daily) and installs it on request:
/// downloads the installer, verifies size and SHA-256 from GitHub, runs it silently and lets it restart Pastebird.
/// Only the release information and the installer are requested; nothing about the user is sent.
/// Not used in the Microsoft Store version, which the Store keeps up to date.
/// </summary>
internal sealed class UpdateService : IDisposable
{
    private static readonly TimeSpan FirstCheckDelay = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(24);

    private readonly HttpClient _http;
    private readonly DispatcherTimer _timer = new();
    private bool _installing;

    public UpdateService()
    {
        _http = new HttpClient { Timeout = TimeSpan.FromMinutes(5) };
        _http.DefaultRequestHeaders.UserAgent.ParseAdd($"Pastebird/{AppInfo.Version}");
        _timer.Tick += async (_, _) =>
        {
            _timer.Interval = CheckInterval;
            await CheckAsync();
        };
    }

    public static bool IsSupported => !AutoStart.IsPackaged;

    /// <summary>The newer version that was found, if any.</summary>
    public UpdateInfo? Available { get; private set; }

    /// <summary>Raised on the UI thread when a newer version is found for the first time.</summary>
    public event Action<UpdateInfo>? UpdateFound;

    public bool Enabled
    {
        get => _timer.IsEnabled;
        set
        {
            if (value == _timer.IsEnabled || !IsSupported) return;
            if (value)
            {
                _timer.Interval = FirstCheckDelay;
                _timer.Start();
            }
            else
            {
                _timer.Stop();
            }
        }
    }

    /// <summary>Asks GitHub for the latest release and updates <see cref="Available"/>. Returns false when GitHub couldn't be reached.</summary>
    public async Task<bool> CheckAsync()
    {
        if (!IsSupported) return false;
        try
        {
            using var response = await _http.GetAsync(AppInfo.LatestReleaseApiUrl);
            if (!response.IsSuccessStatusCode) return false;
            using var json = JsonDocument.Parse(await response.Content.ReadAsStreamAsync());
            var update = Parse(json.RootElement);
            if (update is not null && update.Version > Version.Parse(AppInfo.Version) && update.Version != Available?.Version)
            {
                Available = update;
                UpdateFound?.Invoke(update);
            }
            return true;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or JsonException or FormatException)
        {
            // Offline or GitHub unreachable: try again at the next interval.
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
        }
        return false;
    }

    private static UpdateInfo? Parse(JsonElement release)
    {
        if (release.TryGetProperty("draft", out var draft) && draft.GetBoolean()) return null;
        if (release.TryGetProperty("prerelease", out var pre) && pre.GetBoolean()) return null;
        if (!Version.TryParse(release.GetProperty("tag_name").GetString()?.TrimStart('v', 'V'), out var tag)) return null;
        var version = new Version(tag.Major, tag.Minor, Math.Max(tag.Build, 0)); // "1.1" → 1.1.0, comparable with AppInfo.Version

        foreach (var asset in release.GetProperty("assets").EnumerateArray())
        {
            var name = asset.GetProperty("name").GetString() ?? "";
            if (!name.StartsWith("PastebirdSetup", StringComparison.OrdinalIgnoreCase) || !name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                continue;

            var url = asset.GetProperty("browser_download_url").GetString();
            if (url is null || !url.StartsWith(AppInfo.GitHubUrl + "/releases/download/", StringComparison.Ordinal))
                return null;

            // GitHub publishes "sha256:<hex>" for release assets.
            string? sha256 = asset.TryGetProperty("digest", out var digest) && digest.GetString() is string d && d.StartsWith("sha256:")
                ? d["sha256:".Length..]
                : null;
            return new UpdateInfo(version, url, asset.GetProperty("size").GetInt64(), sha256);
        }
        return null;
    }

    /// <summary>
    /// Downloads and verifies the installer, then starts it silently. Returns true when the installer
    /// is running; the caller must then exit so it can replace Pastebird.exe (it restarts Pastebird afterwards).
    /// </summary>
    public async Task<bool> DownloadAndStartInstallerAsync(UpdateInfo update)
    {
        if (_installing) return false;
        _installing = true;
        try
        {
            var folder = Path.Combine(Path.GetTempPath(), "Pastebird");
            Directory.CreateDirectory(folder);
            var path = Path.Combine(folder, $"PastebirdSetup-{update.Version}.exe");

            await using (var source = await _http.GetStreamAsync(update.DownloadUrl))
            await using (var file = File.Create(path))
                await source.CopyToAsync(file);

            var bytes = await File.ReadAllBytesAsync(path);
            bool valid = bytes.LongLength == update.Size
                && (update.Sha256 is null || Convert.ToHexStringLower(SHA256.HashData(bytes)) == update.Sha256.ToLowerInvariant());
            if (!valid)
            {
                File.Delete(path);
                throw new InvalidDataException($"Downloaded installer for {update.Version} failed verification.");
            }

            Process.Start(new ProcessStartInfo(path, "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART") { UseShellExecute = true });
            return true;
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
            return false;
        }
        finally
        {
            _installing = false;
        }
    }

    public void Dispose()
    {
        _timer.Stop();
        _http.Dispose();
    }
}
