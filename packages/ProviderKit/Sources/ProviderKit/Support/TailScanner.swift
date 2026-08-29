import Foundation

/// Reads a file backwards a chunk at a time, yielding whole lines newest-first.
///
/// Session transcripts grow without bound and the reading we want is almost always in the
/// last few lines, so scanning from the end avoids parsing megabytes of history. The file
/// is opened read-only and never locked — these files belong to other running apps.
enum TailScanner {
    /// Calls `body` with each line from the end of the file until it returns a non-nil
    /// value, then returns that value.
    static func findFromEnd<T>(
        at url: URL,
        chunkSize: Int = 64 * 1024,
        maxBytes: Int = 8 * 1024 * 1024,
        body: (String) -> T?
    ) throws -> T? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let fileSize = Int(try handle.seekToEnd())
        var position = fileSize
        var pending = Data()
        var scanned = 0

        while position > 0 && scanned < maxBytes {
            let readSize = min(chunkSize, position)
            position -= readSize
            try handle.seek(toOffset: UInt64(position))
            guard let chunk = try handle.read(upToCount: readSize) else { break }
            scanned += readSize

            var buffer = chunk
            buffer.append(pending)

            // Everything before the first newline may be an incomplete line; hold it for
            // the next (earlier) chunk to complete.
            let lines = buffer.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            pending = position > 0 ? Data(lines[0]) : Data()

            for slice in lines.dropFirst(position > 0 ? 1 : 0).reversed() {
                guard !slice.isEmpty, let line = String(data: Data(slice), encoding: .utf8) else { continue }
                if let result = body(line) { return result }
            }
        }
        return nil
    }
}
