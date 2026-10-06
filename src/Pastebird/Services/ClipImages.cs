using System.IO;
using System.Security.Cryptography;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Pastebird.Core;

namespace Pastebird.Services;

/// <summary>An image read from the clipboard: the PNG an app put there, or else the bitmap Windows offers for every image.</summary>
internal sealed record ClipboardImage(byte[]? Png, BitmapSource? Bitmap);

/// <summary>Reads, converts and decodes copied images. Everything except <see cref="Read"/> may run on a background thread.</summary>
internal static class ClipImages
{
    private const long MaxPixels = 40_000_000;
    private const int MaxPngBytes = 30 * 1024 * 1024;

    // The popup shows thumbnails at half this size, so they stay sharp up to 200% display scaling.
    private const int ThumbnailHeight = 64;
    private const int ThumbnailMaxWidth = 256;

    /// <summary>Reads the image on the clipboard. Must run on the UI thread; the result is frozen.</summary>
    public static ClipboardImage? Read(IDataObject data)
    {
        // The "PNG" format (browsers, Office, the Snipping Tool) keeps transparency and needs no re-encoding.
        if (data.GetDataPresent("PNG", false) && data.GetData("PNG", false) is MemoryStream png && png.Length <= MaxPngBytes)
            return new ClipboardImage(png.ToArray(), null);

        if (data.GetDataPresent(DataFormats.Bitmap, true) && data.GetData(DataFormats.Bitmap, true) is BitmapSource bitmap)
        {
            if ((long)bitmap.PixelWidth * bitmap.PixelHeight > MaxPixels) return null;

            // Clipboard bitmaps often have an empty alpha channel; drop it so they don't turn transparent.
            var opaque = new FormatConvertedBitmap(bitmap, PixelFormats.Bgr32, null, 0);
            int stride = opaque.PixelWidth * 4;
            var pixels = new byte[stride * opaque.PixelHeight];
            opaque.CopyPixels(pixels, stride, 0);
            var copy = BitmapSource.Create(opaque.PixelWidth, opaque.PixelHeight, 96, 96, PixelFormats.Bgr32, null, pixels, stride);
            copy.Freeze();
            return new ClipboardImage(null, copy);
        }
        return null;
    }

    /// <summary>Turns a copied image into a history item and its data, or returns null when it is too large.</summary>
    public static (ClipItem Item, ClipData Data)? Create(ClipboardImage image)
    {
        var png = image.Png ?? Encode(image.Bitmap!);
        if (png.Length > MaxPngBytes) return null;

        var full = image.Bitmap ?? Decode(png);
        int width = full.PixelWidth, height = full.PixelHeight;
        if ((long)width * height > MaxPixels) return null;

        double scale = Math.Min(1, Math.Min((double)ThumbnailHeight / height, (double)ThumbnailMaxWidth / width));
        var thumbnail = Encode(Decode(png, Math.Max(1, (int)Math.Round(width * scale))));

        var item = new ClipItem
        {
            Kind = ClipKind.Image,
            Content = Convert.ToHexString(SHA256.HashData(png)),
            ImageWidth = width,
            ImageHeight = height,
            Thumbnail = thumbnail,
        };
        return (item, new ClipData { Png = png });
    }

    /// <summary>Decodes a PNG, optionally scaled down to <paramref name="decodeWidth"/> pixels wide. The result is frozen.</summary>
    public static BitmapSource Decode(byte[] png, int decodeWidth = 0)
    {
        var image = new BitmapImage();
        image.BeginInit();
        image.CacheOption = BitmapCacheOption.OnLoad;
        image.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
        image.StreamSource = new MemoryStream(png);
        if (decodeWidth > 0) image.DecodePixelWidth = decodeWidth;
        image.EndInit();
        image.Freeze();
        return image;
    }

    private static byte[] Encode(BitmapSource bitmap)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }
}
