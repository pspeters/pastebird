using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// Clippo icon: a rounded clipboard with a clip on top and a bold "C" on the board.
// Drawn on a 32x32 design grid and scaled per size.
// Run: dotnet run --project tools/IconGen -- src/Clippo/Assets [packaging/msix/Assets]

var outDir = args.Length > 0 ? args[0] : ".";
int[] sizes = [16, 20, 24, 32, 40, 48, 64, 256];
var images = sizes.Select(s => (Size: s, Bitmap: Render(s))).ToList();

WriteIco(Path.Combine(outDir, "clippo.ico"), images);
Console.WriteLine($"Wrote clippo.ico ({images.Count} sizes) to {Path.GetFullPath(outDir)}");

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

        var board = new LinearGradientBrush(Color.FromRgb(0x4A, 0x8C, 0xFF), Color.FromRgb(0x4B, 0x4F, 0xE0), 90);
        var outline = new SolidColorBrush(Color.FromRgb(0x2B, 0x33, 0x9E));
        var white = Brushes.White;

        // Board
        dc.DrawRoundedRectangle(board, null, new Rect(4, 5, 24, 26), 4.5, 4.5);

        // Clip (white pill with a dark rim so it separates from the board)
        double rim = size <= 20 ? 2 : 1.5;
        dc.DrawRoundedRectangle(outline, null, new Rect(10 - rim / 2, 2 - rim / 2, 12 + rim, 6 + rim), 2.5, 2.5);
        dc.DrawRoundedRectangle(white, null, new Rect(10, 2, 12, 6), 2, 2);

        // "C"
        double cx = 16, cy = 19.5, r = size <= 20 ? 5.5 : 5.75;
        double stroke = size <= 20 ? 3.5 : 3.25;
        double a = 50 * Math.PI / 180;
        var start = new Point(cx + r * Math.Cos(a), cy - r * Math.Sin(a));
        var end = new Point(cx + r * Math.Cos(a), cy + r * Math.Sin(a));
        var arc = new StreamGeometry();
        using (var g = arc.Open())
        {
            g.BeginFigure(start, false, false);
            g.ArcTo(end, new Size(r, r), 0, true, SweepDirection.Counterclockwise, true, true);
        }
        dc.DrawGeometry(null, new Pen(white, stroke) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, arc);
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
