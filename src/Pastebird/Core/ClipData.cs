using System.IO;

namespace Pastebird.Core;

/// <summary>
/// The parts of a clipboard item that are too large for the history file: the formatting of copied text
/// (HTML and RTF) or a copied image (PNG). Stored per item by <see cref="LocalStorage"/> and only loaded
/// when the item is pasted or previewed.
/// </summary>
public sealed class ClipData
{
    private const byte Version = 1;

    /// <summary>"HTML Format" as apps put it on the clipboard, including its header.</summary>
    public string? Html { get; init; }
    public string? Rtf { get; init; }
    public byte[]? Png { get; init; }

    public byte[] Serialize()
    {
        using var stream = new MemoryStream();
        using (var writer = new BinaryWriter(stream))
        {
            writer.Write(Version);
            WriteString(writer, Html);
            WriteString(writer, Rtf);
            writer.Write(Png?.Length ?? -1);
            if (Png is not null) writer.Write(Png);
        }
        return stream.ToArray();
    }

    public static ClipData Deserialize(byte[] bytes)
    {
        using var reader = new BinaryReader(new MemoryStream(bytes));
        if (reader.ReadByte() != Version) throw new InvalidDataException("Unknown clipboard data version.");
        var html = ReadString(reader);
        var rtf = ReadString(reader);
        int pngLength = reader.ReadInt32();
        return new ClipData { Html = html, Rtf = rtf, Png = pngLength >= 0 ? reader.ReadBytes(pngLength) : null };
    }

    private static void WriteString(BinaryWriter writer, string? value)
    {
        writer.Write(value is not null);
        if (value is not null) writer.Write(value);
    }

    private static string? ReadString(BinaryReader reader) => reader.ReadBoolean() ? reader.ReadString() : null;
}
