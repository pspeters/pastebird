namespace Pastebird.Core;

/// <summary>Product information shown in Settings → About.</summary>
public static class AppInfo
{
    public const string GitHubUrl = "https://github.com/pspeters/pastebird";
    public const string DonateUrl = "https://ko-fi.com/pastebirdapp";
    public const string ReleasesUrl = GitHubUrl + "/releases/latest";
    public const string ChangelogUrl = "https://pastebird.app/changelog.php";
    public const string LatestReleaseApiUrl = "https://api.github.com/repos/pspeters/pastebird/releases/latest";
    /// <summary>
    /// The updater downloads a new version through here: the website counts that an update happened (only the two
    /// version numbers) and forwards to the installer on GitHub, so its statistics can tell updates from new downloads.
    /// </summary>
    public const string UpdateDownloadUrl = "https://pastebird.app/update.php";

    /// <summary>Pastebird requires Windows 11 (build 22000 or later).</summary>
    public static bool IsSupportedWindows { get; } = Environment.OSVersion.Version.Build >= 22000;

    public static string Version { get; } = typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
}
