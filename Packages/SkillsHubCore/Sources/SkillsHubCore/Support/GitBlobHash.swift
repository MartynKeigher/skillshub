import Foundation

/// The SHA-1 git gives a file's contents (`git hash-object`): SHA-1 of `blob <size>\0` followed
/// by the bytes. SkillsFlow records it for every file, so the app can check a download against
/// the index and tell whether an installed file was edited.
public enum GitBlobHash {
    public static func of(_ data: Data) -> String {
        var sha = SHA1()
        sha.update(Data("blob \(data.count)\0".utf8))
        sha.update(data)
        return sha.hexDigest()
    }

    /// Hashes a file in chunks, so large files aren't read into memory at once.
    public static func ofFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        var sha = SHA1()
        sha.update(Data("blob \(size?.int64Value ?? 0)\0".utf8))
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            sha.update(chunk)
        }
        return sha.hexDigest()
    }
}

/// SHA-1, used only to compute git object IDs, never for security decisions on its own.
struct SHA1 {
    private var h: (UInt32, UInt32, UInt32, UInt32, UInt32) = (0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0)
    private var buffer: [UInt8] = []
    private var length: UInt64 = 0

    mutating func update(_ data: Data) {
        length += UInt64(data.count)
        buffer.append(contentsOf: data)
        var offset = 0
        while buffer.count - offset >= 64 {
            processBlock(buffer, at: offset)
            offset += 64
        }
        buffer.removeFirst(offset)
    }

    mutating func hexDigest() -> String {
        var tail = buffer
        tail.append(0x80)
        while tail.count % 64 != 56 { tail.append(0) }
        let bits = length * 8
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        for offset in stride(from: 0, to: tail.count, by: 64) { processBlock(tail, at: offset) }
        buffer = []
        return [h.0, h.1, h.2, h.3, h.4].map { String(format: "%08x", $0) }.joined()
    }

    private mutating func processBlock(_ bytes: [UInt8], at offset: Int) {
        var w = [UInt32](repeating: 0, count: 80)
        for i in 0 ..< 16 {
            let j = offset + i * 4
            w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j + 1]) << 16 | UInt32(bytes[j + 2]) << 8 | UInt32(bytes[j + 3])
        }
        for i in 16 ..< 80 {
            let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
            w[i] = x << 1 | x >> 31
        }
        var (a, b, c, d, e) = h
        for i in 0 ..< 80 {
            let (f, k): (UInt32, UInt32) = switch i {
            case 0 ..< 20: ((b & c) | (~b & d), 0x5A82_7999)
            case 20 ..< 40: (b ^ c ^ d, 0x6ED9_EBA1)
            case 40 ..< 60: ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
            default: (b ^ c ^ d, 0xCA62_C1D6)
            }
            let temp = (a << 5 | a >> 27) &+ f &+ e &+ k &+ w[i]
            e = d
            d = c
            c = b << 30 | b >> 2
            b = a
            a = temp
        }
        h = (h.0 &+ a, h.1 &+ b, h.2 &+ c, h.3 &+ d, h.4 &+ e)
    }
}
