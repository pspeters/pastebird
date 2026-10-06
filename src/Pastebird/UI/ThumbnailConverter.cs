using System.Globalization;
using System.Windows.Data;
using Pastebird.Core;
using Pastebird.Services;

namespace Pastebird.UI;

/// <summary>Turns the PNG thumbnail of an image item into an image for the popup list.</summary>
public sealed class ThumbnailConverter : IValueConverter
{
    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not byte[] { Length: > 0 } png) return null;
        try
        {
            return ClipImages.Decode(png);
        }
        catch (Exception ex)
        {
            LocalStorage.Log(ex);
            return null;
        }
    }

    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotSupportedException();
}
