import Foundation

/// RFC 4648 Base32, the encoding sites use for setup keys.
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    /// Sites print keys in lower case, grouped with spaces or hyphens, with or without padding; all of those decode.
    public static func decode(_ text: String) -> Data? {
        let symbols = text.uppercased().filter { !" -=\t\n".contains($0) }
        guard !symbols.isEmpty else { return nil }
        var bytes = Data(), buffer: UInt32 = 0, bits = 0
        for symbol in symbols {
            guard let value = alphabet.firstIndex(of: symbol) else { return nil }
            buffer = buffer << 5 | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8(truncatingIfNeeded: buffer >> UInt32(bits)))
            }
        }
        return bytes.isEmpty ? nil : bytes
    }

    public static func encode(_ data: Data) -> String {
        var text = "", buffer: UInt32 = 0, bits = 0
        for byte in data {
            buffer = buffer << 8 | UInt32(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                text.append(alphabet[Int(buffer >> UInt32(bits) & 31)])
            }
        }
        if bits > 0 { text.append(alphabet[Int(buffer << UInt32(5 - bits) & 31)]) }
        return text
    }
}
