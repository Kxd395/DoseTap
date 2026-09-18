import Foundation
#if canImport(Compression)
import Compression
#endif

/// Deterministic ZIP with raw DEFLATE where available and a portable stored fallback.
enum ExcelWorkbookZIP {
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = (value >> 1) ^ ((value & 1) == 1 ? 0xedb88320 : 0) }
        return value
    }

    static func archive(parts: [String: Data]) throws -> Data {
        guard parts.count <= Int(UInt16.max) else { throw WorkbookXML.failure("There are too many workbook parts for this archive format.") }
        var result = Data(); var central = Data()
        for name in parts.keys.sorted() {
            let nameData = Data(name.utf8); let body = parts[name]!
            guard nameData.count <= Int(UInt16.max), body.count <= Int(UInt32.max), result.count <= Int(UInt32.max) else {
                throw WorkbookXML.failure("The workbook is too large for this archive format; export a smaller range.")
            }
            let offset = UInt32(result.count)
            let checksum = crc(body)
            let compressed = deflated(body)
            let payload = compressed ?? body
            let method: UInt16 = compressed == nil ? 0 : 8
            result.le(UInt32(0x04034b50)); result.le(UInt16(20)); result.le(UInt16(0x0800))
            result.le(method); result.le(UInt16(0)); result.le(UInt16(0x0021)) // 1980-01-01, deterministic.
            result.le(checksum); result.le(UInt32(payload.count)); result.le(UInt32(body.count))
            result.le(UInt16(nameData.count)); result.le(UInt16(0)); result.append(nameData); result.append(payload)
            central.le(UInt32(0x02014b50)); central.le(UInt16(20)); central.le(UInt16(20)); central.le(UInt16(0x0800))
            central.le(method); central.le(UInt16(0)); central.le(UInt16(0x0021))
            central.le(checksum); central.le(UInt32(payload.count)); central.le(UInt32(body.count))
            central.le(UInt16(nameData.count)); central.le(UInt16(0)); central.le(UInt16(0)); central.le(UInt16(0))
            central.le(UInt16(0)); central.le(UInt32(0)); central.le(offset); central.append(nameData)
        }
        guard result.count <= Int(UInt32.max), central.count <= Int(UInt32.max),
            result.count + central.count + 22 <= Int(UInt32.max) else {
            throw WorkbookXML.failure("The workbook is too large for this archive format; export a smaller range.")
        }
        let centralOffset = UInt32(result.count)
        result.append(central)
        result.le(UInt32(0x06054b50)); result.le(UInt16(0)); result.le(UInt16(0))
        result.le(UInt16(parts.count)); result.le(UInt16(parts.count)); result.le(UInt32(central.count)); result.le(centralOffset)
        result.le(UInt16(0))
        return result
    }

    private static func deflated(_ data: Data) -> Data? {
        #if canImport(Compression)
        guard data.count >= 128 else { return nil }
        // Apple documents COMPRESSION_ZLIB as raw RFC1951 DEFLATE (windowBits -15),
        // which is ZIP method 8. No zlib/gzip header stripping is required.
        // https://developer.apple.com/documentation/compression/compression_zlib
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        return data.withUnsafeBytes { bytes -> Data? in
            guard let source = bytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(dst_ptr: buffer, dst_size: bufferSize,
                src_ptr: source, src_size: data.count, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = source; stream.src_size = data.count
            var result = Data()
            while true {
                stream.dst_ptr = buffer; stream.dst_size = bufferSize
                let remaining = stream.src_size
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                guard status != COMPRESSION_STATUS_ERROR else { return nil }
                let count = bufferSize - stream.dst_size
                // Retaining the original is cheaper and always valid if compression cannot shrink it.
                guard result.count + count < data.count else { return nil }
                result.append(buffer, count: count)
                if status == COMPRESSION_STATUS_END { return result }
                guard count > 0 || stream.src_size < remaining else { return nil }
            }
        }
        #else
        return nil
        #endif
    }

    private static func crc(_ bytes: Data) -> UInt32 {
        var value = UInt32.max
        for byte in bytes { value = (value >> 8) ^ crcTable[Int((value ^ UInt32(byte)) & 0xff)] }
        return ~value
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ integer: T) {
        var value = integer.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}
