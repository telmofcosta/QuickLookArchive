import Foundation

struct ArchiveEntry {
    let path: String
    let size: Int64
    let modified: Date?
    let isDirectory: Bool
}

struct ArchiveError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ArchiveReader {
    private static let archiveOK: Int32 = 0
    private static let archiveEOF: Int32 = 1
    private static let formatRaw: Int32 = 0x90000
    /// A single compressed file (foo.txt.gz) is decompressed only this far to learn its size.
    private static let rawSizeProbeLimit = 256 << 20

    /// Drops empty and "." components so "./a//b" and "a/b" compare equal.
    static func normalize(_ path: String) -> String {
        path.split(separator: "/").filter { $0 != "." }.joined(separator: "/")
    }

    private static func open(_ url: URL) throws -> OpaquePointer {
        guard let a = archive_read_new() else { throw ArchiveError(message: "Cannot create archive reader") }
        _ = archive_read_support_filter_all(a)
        _ = archive_read_support_format_all(a)
        _ = archive_read_support_format_raw(a)

        guard archive_read_open_filename(a, url.path, 65_536) == archiveOK else {
            defer { _ = archive_read_free(a) }
            throw ArchiveError(message: String(cString: archive_error_string(a)))
        }
        return a
    }

    /// Lists entries without extracting anything. Stops after `limit` entries.
    static func list(url: URL, limit: Int = 50_000) throws -> (entries: [ArchiveEntry], truncated: Bool) {
        let a = try open(url)
        defer { _ = archive_read_free(a) }

        var entries: [ArchiveEntry] = []
        var entry: OpaquePointer?
        while true {
            let rc = archive_read_next_header(a, &entry)
            if rc == archiveEOF { return (entries, false) }
            if rc < archiveOK { throw ArchiveError(message: String(cString: archive_error_string(a))) }
            guard let entry else { continue }
            if entries.count >= limit { return (entries, true) }

            if archive_format(a) == formatRaw {
                // Compressed file with no archive inside: one entry named after the file.
                return ([ArchiveEntry(path: rawName(url), size: rawSize(a), modified: nil, isDirectory: false)], false)
            }

            let path = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
            let mtime = archive_entry_mtime(entry)
            entries.append(ArchiveEntry(
                path: path,
                size: archive_entry_size(entry),
                modified: mtime == 0 ? nil : Date(timeIntervalSince1970: TimeInterval(mtime)),
                isDirectory: archive_entry_filetype(entry) & 0o170000 == 0o040000
            ))
            _ = archive_read_data_skip(a)
        }
    }

    /// A compressed file with no archive inside is shown as one entry named after the file.
    private static func rawName(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Reads one entry into memory, at most `limit` bytes. Returns nil if the path is not in the archive.
    static func read(url: URL, path: String, limit: Int) throws -> (data: Data, truncated: Bool)? {
        let a = try open(url)
        defer { _ = archive_read_free(a) }

        var entry: OpaquePointer?
        while true {
            let rc = archive_read_next_header(a, &entry)
            if rc == archiveEOF { return nil }
            if rc < archiveOK { throw ArchiveError(message: String(cString: archive_error_string(a))) }
            guard let entry else { continue }

            let name = archive_format(a) == formatRaw
                ? rawName(url)
                : archive_entry_pathname(entry).map { String(cString: $0) } ?? ""
            guard normalize(name) == path else {
                _ = archive_read_data_skip(a)
                continue
            }

            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1 << 20)
            while data.count <= limit {
                let n = archive_read_data(a, &buffer, buffer.count)
                if n < 0 { throw ArchiveError(message: String(cString: archive_error_string(a))) }
                if n == 0 { return (data, false) }
                data.append(buffer, count: n)
            }
            return (data.prefix(limit), true)
        }
    }

    /// Decompressed size of a raw stream, or -1 if it is larger than the probe limit.
    private static func rawSize(_ a: OpaquePointer) -> Int64 {
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var total = 0
        while true {
            let n = archive_read_data(a, &buffer, buffer.count)
            if n <= 0 { return Int64(total) }
            total += n
            if total > rawSizeProbeLimit { return -1 }
        }
    }
}
