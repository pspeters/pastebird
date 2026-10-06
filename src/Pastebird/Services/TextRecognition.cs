using System.IO;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Pastebird.Core;

namespace Pastebird.Services;

/// <summary>
/// Reads the text in copied images with the text recognition built into Windows (Windows.Media.Ocr), so screenshots
/// can be found by the words on them. Runs on this pc, without internet, in the languages of the Windows profile.
/// </summary>
internal static class TextRecognition
{
    private const int MaxChars = 20_000;

    private static readonly Lazy<OcrEngine?> Engine = new(() =>
    {
        try { return OcrEngine.TryCreateFromUserProfileLanguages(); }
        catch (Exception ex) { LocalStorage.Log(ex); return null; }
    });

    /// <summary>
    /// The text in the image, one line per line of text; "" when there is none. Null when Windows has no text
    /// recognition for the user's languages, so it can be tried again later.
    /// </summary>
    public static async Task<string?> RecognizeAsync(byte[] png)
    {
        if (Engine.Value is not { } engine) return null;

        using var stream = new MemoryStream(png).AsRandomAccessStream();
        var decoder = await BitmapDecoder.CreateAsync(stream);

        // Windows refuses larger images; scale those down, keeping the aspect ratio.
        uint max = OcrEngine.MaxImageDimension;
        double scale = Math.Min(1, (double)max / Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        var transform = new BitmapTransform
        {
            ScaledWidth = Math.Max(1, (uint)(decoder.PixelWidth * scale)),
            ScaledHeight = Math.Max(1, (uint)(decoder.PixelHeight * scale)),
            InterpolationMode = BitmapInterpolationMode.Fant,
        };
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied,
            transform, ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage);

        var result = await engine.RecognizeAsync(bitmap);
        var text = string.Join("\r\n", result.Lines.Select(l => l.Text)).Trim();
        return text.Length > MaxChars ? text[..MaxChars] : text;
    }
}
