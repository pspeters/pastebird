using System.IO;
using Microsoft.Win32;
using static Clippo.Interop.NativeMethods;

namespace Clippo.Services;

/// <summary>
/// Start-with-Windows. Normally via the per-user Run key (no admin rights needed); inside an MSIX
/// package (Microsoft Store) via the package's StartupTask, because registry writes are virtualized there.
/// </summary>
internal static class AutoStart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "Clippo";
    private const string StartupTaskId = "ClippoStartup"; // must match AppxManifest.xml

    public static bool IsPackaged { get; } = DetectPackage();

    /// <summary>Turns autostart on or off and returns the resulting state.</summary>
    public static async Task<bool> ApplyAsync(bool enabled)
    {
        if (IsPackaged)
            return await ApplyPackagedAsync(enabled);
        ApplyRunKey(enabled);
        return enabled;
    }

    /// <summary>The real autostart state of the package (the user may change it in Task Manager), or null when not packaged.</summary>
    public static async Task<bool?> GetPackagedStateAsync()
    {
#if MSIX
        if (IsPackaged)
        {
            var task = await Windows.ApplicationModel.StartupTask.GetAsync(StartupTaskId);
            return task.State is Windows.ApplicationModel.StartupTaskState.Enabled
                or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
        }
#endif
        return await Task.FromResult<bool?>(null);
    }

    private static async Task<bool> ApplyPackagedAsync(bool enabled)
    {
#if MSIX
        var task = await Windows.ApplicationModel.StartupTask.GetAsync(StartupTaskId);
        if (enabled)
        {
            // Returns DisabledByUser when it was switched off in Task Manager; only the user can undo that.
            var state = await task.RequestEnableAsync();
            return state is Windows.ApplicationModel.StartupTaskState.Enabled
                or Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
        }
        task.Disable();
        return task.State == Windows.ApplicationModel.StartupTaskState.EnabledByPolicy;
#else
        return await Task.FromResult(false);
#endif
    }

    private static bool DetectPackage()
    {
        int length = 0;
        return GetCurrentPackageFullName(ref length, null) != APPMODEL_ERROR_NO_PACKAGE;
    }

    private static void ApplyRunKey(bool enabled)
    {
        var path = Environment.ProcessPath;
        if (path is null || Path.GetFileName(path).Equals("dotnet.exe", StringComparison.OrdinalIgnoreCase))
            return; // started via "dotnet Clippo.dll" (development): don't register the host

        using var key = Registry.CurrentUser.CreateSubKey(RunKey);
        if (enabled)
            key.SetValue(ValueName, $"\"{path}\"");
        else
            key.DeleteValue(ValueName, throwOnMissingValue: false);
    }
}

/// <summary>Light/dark detection and dark-mode support for native menus.</summary>
internal static class SystemTheme
{
    private static readonly bool SupportsDarkMenus = Environment.OSVersion.Version.Build >= 18362;

    public static bool IsDark()
    {
        using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
        return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
    }

    /// <summary>Lets native popup menus (the tray menu) follow the Windows app theme.</summary>
    public static void EnableDarkMenus(IntPtr ownerWindow)
    {
        if (!SupportsDarkMenus) return;
        try
        {
            SetPreferredAppMode(1); // AllowDark
            AllowDarkModeForWindow(ownerWindow, true);
            RefreshMenus();
        }
        catch (Exception)
        {
            // Undocumented API; menus simply stay light if it is unavailable.
        }
    }

    public static void RefreshMenus()
    {
        if (!SupportsDarkMenus) return;
        try
        {
            RefreshImmersiveColorPolicyState();
            FlushMenuThemes();
        }
        catch (Exception)
        {
        }
    }
}
