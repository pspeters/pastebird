namespace Pastebird.Core;

/// <summary>Product information shown in Settings → About.</summary>
public static class AppInfo
{
    public const string GitHubUrl = "https://github.com/pspeters/pastebird";
    public const string DonateUrl = "https://ko-fi.com/pastebirdapp";

    /// <summary>Pastebird requires Windows 11 (build 22000 or later).</summary>
    public static bool IsSupportedWindows { get; } = Environment.OSVersion.Version.Build >= 22000;

    public static string Version { get; } = typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
}
