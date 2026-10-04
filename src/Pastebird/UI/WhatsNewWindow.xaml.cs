using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media.Imaging;
using Pastebird.Core;

namespace Pastebird.UI;

/// <summary>"What's new": the changelog entries of the given releases, from the CHANGELOG.md built into the app.</summary>
public partial class WhatsNewWindow : Window
{
    public WhatsNewWindow(IReadOnlyList<ChangelogRelease> releases, bool afterUpdate)
    {
        InitializeComponent();
        MaxHeight = SystemParameters.WorkArea.Height - 40;
        AppIcon.Source = BitmapFrame.Create(new Uri("pack://application:,,,/Pastebird;component/Assets/pastebird.ico"));

        Heading.Text = afterUpdate ? Loc.T("whatsnew.updated", AppInfo.Version) : Loc.T("whatsnew.title");
        Subheading.Text = Loc.T("whatsnew.english");
        Subheading.Visibility = Loc.T("whatsnew.english").Length > 0 ? Visibility.Visible : Visibility.Collapsed;

        foreach (var release in releases)
            Releases.Children.Add(BuildCard(release));
        if (releases.Count == 0)
            Releases.Children.Add(new TextBlock { Text = Loc.T("whatsnew.empty"), TextWrapping = TextWrapping.Wrap });

        AllChangesButton.Click += (_, _) => App.OpenUrl($"{AppInfo.ChangelogUrl}?lang={Loc.T("whatsnew.culture")[..2]}");
        CloseButton.Click += (_, _) => Close();
    }

    private Border BuildCard(ChangelogRelease release)
    {
        var panel = new StackPanel();
        var title = new TextBlock { FontSize = 15, FontWeight = FontWeights.SemiBold };
        title.Inlines.Add(new Run(Loc.T("about.version", release.Version.ToString(3))));
        if (FormatDate(release.Date) is { } date)
        {
            var dateRun = new Run("  ·  " + date) { FontWeight = FontWeights.Normal, FontSize = 12 };
            dateRun.SetResourceReference(TextElement.ForegroundProperty, "TextFillColorSecondaryBrush");
            title.Inlines.Add(dateRun);
        }
        panel.Children.Add(title);

        foreach (var section in release.Sections)
        {
            if (section.Type.Length > 0)
            {
                // "Added" → "New"/"Nieuw"; unknown types are shown as written.
                var key = "whatsnew.type." + section.Type.ToLowerInvariant();
                var translated = Loc.T(key);
                var label = new TextBlock
                {
                    Text = translated == key ? section.Type : translated,
                    FontSize = 12, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 10, 0, 4),
                };
                label.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
                panel.Children.Add(label);
            }
            foreach (var item in section.Items)
                panel.Children.Add(BuildBullet(item));
        }
        return new Border { Style = (Style)FindResource("Card"), Child = panel };
    }

    private static Grid BuildBullet(string item)
    {
        var grid = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        grid.Children.Add(new TextBlock { Text = "•", Margin = new Thickness(2, 0, 10, 0) });

        var text = new TextBlock { TextWrapping = TextWrapping.Wrap };
        foreach (var (part, bold) in Changelog.InlineRuns(item))
            text.Inlines.Add(new Run(part) { FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);
        return grid;
    }

    private static string? FormatDate(string date)
    {
        if (!DateTime.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
            return null;
        var culture = CultureInfo.GetCultureInfo(Loc.T("whatsnew.culture"));
        return parsed.ToString("d MMMM yyyy", culture);
    }
}
