using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// Pastebird icon: a chubby white bird on a sky-blue tile, carrying a sticky note in its beak (the "paste").
// Drawn on a 32x32 design grid and scaled per size.
// Run: dotnet run --project tools/IconGen -- src/Pastebird/Assets [packaging/msix/Assets]

var outDir = args.Length > 0 ? args[0] : ".";
int[] sizes = [16, 20, 24, 32, 40, 48, 64, 256];
var images = sizes.Select(s => (Size: s, Bitmap: Render(s))).ToList();

WriteIco(Path.Combine(outDir, "pastebird.ico"), images);
if (Environment.GetEnvironmentVariable("ICON_PREVIEW") is { } preview) // optional 256 px PNG for a quick look
    File.WriteAllBytes(preview, EncodePng(images[^1].Bitmap));
Console.WriteLine($"Wrote pastebird.ico ({images.Count} sizes) to {Path.GetFullPath(outDir)}");

// Optional: Microsoft Store (MSIX) assets. Qualified names are resolved by resources.pri (makepri).
if (args.Length > 1)
{
    var msixDir = Directory.CreateDirectory(args[1]).FullName;
    void Png(string name, int icon, int canvas = 0) => File.WriteAllBytes(Path.Combine(msixDir, name), EncodePng(Render(icon, canvas)));

    Png("Square44x44Logo.scale-100.png", 44);
    Png("Square44x44Logo.scale-200.png", 88);
    foreach (var t in new[] { 16, 24, 32, 48, 256 })
    {
        Png($"Square44x44Logo.targetsize-{t}.png", t);
        Png($"Square44x44Logo.targetsize-{t}_altform-unplated.png", t);
    }
    Png("Square150x150Logo.scale-100.png", 100, 150);
    Png("Square150x150Logo.scale-200.png", 200, 300);
    Png("StoreLogo.scale-100.png", 50);
    Png("StoreLogo.scale-200.png", 100);
    Console.WriteLine($"Wrote MSIX assets to {msixDir}");
}

/// <summary>Renders the icon at <paramref name="size"/> px, centered on an optional larger transparent canvas.</summary>
static BitmapSource Render(int size, int canvas = 0)
{
    canvas = Math.Max(canvas, size);
    var visual = new DrawingVisual();
    using (var dc = visual.RenderOpen())
    {
        dc.PushTransform(new TranslateTransform((canvas - size) / 2.0, (canvas - size) / 2.0));
        dc.PushTransform(new ScaleTransform(size / 32.0, size / 32.0));

        bool small = size <= 20; // tray sizes: fewer details, bolder shapes

        var sky = new LinearGradientBrush(Color.FromRgb(0x38, 0xBD, 0xF8), Color.FromRgb(0x25, 0x5F, 0xEB), 90);
        var white = Brushes.White;
        var wing = new SolidColorBrush(Color.FromRgb(0xBF, 0xDB, 0xFE));
        var beak = new SolidColorBrush(Color.FromRgb(0xF5, 0x9E, 0x0B));
        var eye = new SolidColorBrush(Color.FromRgb(0x1E, 0x29, 0x3B));
        var note = new SolidColorBrush(Color.FromRgb(0xFE, 0xF0, 0x8A));
        var noteLine = new SolidColorBrush(Color.FromRgb(0xCA, 0x8A, 0x04));

        // Tile
        dc.DrawRoundedRectangle(sky, null, new Rect(2, 2, 28, 28), 7, 7);

        // Note held in the beak (the "paste"), behind the beak
        if (!small)
        {
            dc.PushTransform(new RotateTransform(14, 26.5, 19));
            dc.DrawRoundedRectangle(note, null, new Rect(23.5, 15.5, 6, 7), 1, 1);
            var line = new Pen(noteLine, 0.6);
            dc.DrawLine(line, new Point(24.8, 18), new Point(28.2, 18));
            dc.DrawLine(line, new Point(24.8, 19.8), new Point(27.4, 19.8));
            dc.Pop();
        }

        // Beak
        var beakShape = new StreamGeometry();
        using (var g = beakShape.Open())
        {
            g.BeginFigure(new Point(22.5, 11.6), true, true);
            g.LineTo(new Point(small ? 27.5 : 27, 13.9), true, true);
            g.LineTo(new Point(22.5, 16.2), true, true);
        }
        dc.DrawGeometry(beak, null, beakShape);

        // Chubby bird: round body + head + tail, as one white shape
        var tail = new StreamGeometry();
        using (var g = tail.Open())
        {
            g.BeginFigure(new Point(9.5, 16.5), true, true);
            g.LineTo(new Point(4, 11.5), true, true);
            g.LineTo(new Point(6.5, 21.5), true, true);
        }
        Geometry bird = new CombinedGeometry(GeometryCombineMode.Union,
            new EllipseGeometry(new Point(14.5, 19), 9, 8),
            new EllipseGeometry(new Point(18.5, 13.5), 5.5, 5.5));
        bird = new CombinedGeometry(GeometryCombineMode.Union, bird, tail);
        dc.DrawGeometry(white, null, bird);

        // Wing
        var wingShape = new StreamGeometry();
        using (var g = wingShape.Open())
        {
            g.BeginFigure(new Point(8, 18), true, true);
            g.QuadraticBezierTo(new Point(13.5, 13.5), new Point(19, 18.5), true, true);
            g.QuadraticBezierTo(new Point(13, 24.5), new Point(8, 18), true, true);
        }
        dc.DrawGeometry(wing, null, wingShape);

        // Eye
        if (!small)
            dc.DrawEllipse(eye, null, new Point(20, 12.3), 1.25, 1.25);
    }

    var bitmap = new RenderTargetBitmap(canvas, canvas, 96, 96, PixelFormats.Pbgra32);
    bitmap.Render(visual);
    return new FormatConvertedBitmap(bitmap, PixelFormats.Bgra32, null, 0);
}

static byte[] EncodePng(BitmapSource bitmap)
{
    var encoder = new PngBitmapEncoder();
    encoder.Frames.Add(BitmapFrame.Create(bitmap));
    using var ms = new MemoryStream();
    encoder.Save(ms);
    return ms.ToArray();
}

// Classic 32-bit DIB entry (BITMAPINFOHEADER + bottom-up BGRA + empty AND mask); readable by every API.
static byte[] EncodeDib(BitmapSource bitmap)
{
    int size = bitmap.PixelWidth;
    var pixels = new byte[size * size * 4];
    bitmap.CopyPixels(pixels, size * 4, 0);
    int maskStride = ((size + 31) / 32) * 4;

    using var ms = new MemoryStream();
    using var w = new BinaryWriter(ms);
    w.Write(40); w.Write(size); w.Write(size * 2);
    w.Write((ushort)1); w.Write((ushort)32);
    w.Write(0); w.Write(pixels.Length + maskStride * size);
    w.Write(0); w.Write(0); w.Write(0); w.Write(0);
    for (int y = size - 1; y >= 0; y--) w.Write(pixels, y * size * 4, size * 4);
    w.Write(new byte[maskStride * size]);
    return ms.ToArray();
}

static void WriteIco(string path, List<(int Size, BitmapSource Bitmap)> images)
{
    var data = images.Select(i => i.Size >= 256 ? EncodePng(i.Bitmap) : EncodeDib(i.Bitmap)).ToList();
    using var w = new BinaryWriter(File.Create(path));
    w.Write((ushort)0); w.Write((ushort)1); w.Write((ushort)images.Count);
    int offset = 6 + 16 * images.Count;
    for (int i = 0; i < images.Count; i++)
    {
        int size = images[i].Size;
        w.Write((byte)(size >= 256 ? 0 : size)); w.Write((byte)(size >= 256 ? 0 : size));
        w.Write((byte)0); w.Write((byte)0);
        w.Write((ushort)1); w.Write((ushort)32);
        w.Write(data[i].Length); w.Write(offset);
        offset += data[i].Length;
    }
    foreach (var d in data) w.Write(d);
}
