import Foundation
import zlib

/// Reads central-directory lengths (including descriptor-based ZIPs) without writing archive paths to disk.
enum PortableZIPReader {
    static let maximumExpandedBytes = 104_857_600
    static func entries(_ data: Data) throws -> [String: Data] {
        guard data.count >= 22, data.count <= maximumExpandedBytes else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = [UInt8](data)
        func u16(_ offset: Int) throws -> Int { guard offset >= 0, offset + 2 <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }; return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        func u32(_ offset: Int) throws -> Int { try u16(offset) | u16(offset + 2) << 16 }
        let floor = max(0, bytes.count - 65_557)
        guard let end = stride(from: bytes.count - 22, through: floor, by: -1).first(where: { index in
            bytes[index] == 0x50 && bytes[index + 1] == 0x4b && bytes[index + 2] == 5 && bytes[index + 3] == 6
        }), try u16(end + 4) == 0, try u16(end + 6) == 0 else { throw CocoaError(.fileReadCorruptFile) }
        let count = try u16(end + 10), centralSize = try u32(end + 12)
        var cursor = try u32(end + 16), total = 0
        guard count < 10_000, cursor + centralSize <= end else { throw CocoaError(.fileReadCorruptFile) }
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard try u32(cursor) == 0x02014b50 else { throw CocoaError(.fileReadCorruptFile) }
            let flags = try u16(cursor + 8), method = try u16(cursor + 10), checksum = try u32(cursor + 16)
            let compressed = try u32(cursor + 20), expanded = try u32(cursor + 24), nameLength = try u16(cursor + 28)
            let extraLength = try u16(cursor + 30), commentLength = try u16(cursor + 32), local = try u32(cursor + 42)
            guard flags & 1 == 0, [0, 8].contains(method), nameLength > 0, cursor + 46 + nameLength <= bytes.count,
                  expanded <= 52_428_800, total + expanded <= maximumExpandedBytes,
                  let name = String(bytes: bytes[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.split(separator: "/").contains("..") else { throw CocoaError(.fileReadCorruptFile) }
            total += expanded
            guard try u32(local) == 0x04034b50 else { throw CocoaError(.fileReadCorruptFile) }
            let start = try local + 30 + u16(local + 26) + u16(local + 28)
            guard start >= 0, start + compressed <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }
            if !name.hasSuffix("/") {
                guard result[name] == nil else { throw CocoaError(.fileReadCorruptFile) }
                let packed = Data(bytes[start..<(start + compressed)])
                let unpacked = method == 0 ? packed : try inflate(packed, size: expanded)
                guard unpacked.count == expanded else { throw CocoaError(.fileReadCorruptFile) }
                let crc = unpacked.withUnsafeBytes { crc32(0, $0.baseAddress?.assumingMemoryBound(to: Bytef.self), uInt($0.count)) }
                guard crc == checksum else { throw CocoaError(.fileReadCorruptFile) }
                result[name] = unpacked
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { inflateEnd(&stream) }
        var result = Data(count: max(1, size))
        let code = input.withUnsafeBytes { source in result.withUnsafeMutableBytes { target in
            stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress?.assumingMemoryBound(to: Bytef.self))
            stream.avail_in = uInt(source.count)
            stream.next_out = target.baseAddress?.assumingMemoryBound(to: Bytef.self)
            stream.avail_out = uInt(target.count)
            return zlib.inflate(&stream, Z_FINISH)
        } }
        guard code == Z_STREAM_END, stream.total_out == size, stream.avail_in == 0 else { throw CocoaError(.fileReadCorruptFile) }
        result.count = size
        return result
    }
}
