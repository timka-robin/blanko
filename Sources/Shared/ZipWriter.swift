import Foundation

/// Minimal ZIP writer (store method, no compression).
/// Enough for Office Open XML packages (.docx/.xlsx) that Word and Excel accept.
enum ZipWriter {
    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    static func archive(entries: [(path: String, data: Data)]) -> Data {
        var body = Data()
        var central = Data()
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0x0021  // 1980-01-01

        for entry in entries {
            let name = Array(entry.path.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)
            let offset = UInt32(body.count)

            body.appendLE32(0x0403_4B50)
            body.appendLE16(20)
            body.appendLE16(0)
            body.appendLE16(0)
            body.appendLE16(dosTime)
            body.appendLE16(dosDate)
            body.appendLE32(crc)
            body.appendLE32(size)
            body.appendLE32(size)
            body.appendLE16(UInt16(name.count))
            body.appendLE16(0)
            body.append(contentsOf: name)
            body.append(entry.data)

            central.appendLE32(0x0201_4B50)
            central.appendLE16(20)
            central.appendLE16(20)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(dosTime)
            central.appendLE16(dosDate)
            central.appendLE32(crc)
            central.appendLE32(size)
            central.appendLE32(size)
            central.appendLE16(UInt16(name.count))
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE16(0)
            central.appendLE32(0)
            central.appendLE32(offset)
            central.append(contentsOf: name)
        }

        var output = body
        let centralOffset = UInt32(body.count)
        output.append(central)
        output.appendLE32(0x0605_4B50)
        output.appendLE16(0)
        output.appendLE16(0)
        output.appendLE16(UInt16(entries.count))
        output.appendLE16(UInt16(entries.count))
        output.appendLE32(UInt32(central.count))
        output.appendLE32(centralOffset)
        output.appendLE16(0)
        return output
    }
}

private extension Data {
    mutating func appendLE16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
