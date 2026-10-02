namespace Pastebird.Core;

/// <summary>Product information shown in Settings → About.</summary>
public static class AppInfo
{
    public const string GitHubUrl = "https://github.com/pspeters/pastebird";
    public const string DonateUrl = "https://buymeacoffee.com/pastebird";

    public static string Version { get; } = typeof(AppInfo).Assembly.GetName().Version?.ToString(3) ?? "1.0.0";
}
