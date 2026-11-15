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

    /// Lists entries without extracting anything. Stops after `limit` entries.
    static func list(url: URL, limit: Int = 50_000) throws -> (entries: [ArchiveEntry], truncated: Bool) {
        guard let a = archive_read_new() else { throw ArchiveError(message: "Cannot create archive reader") }
        defer { _ = archive_read_free(a) }
        _ = archive_read_support_filter_all(a)
        _ = archive_read_support_format_all(a)

        guard archive_read_open_filename(a, url.path, 65_536) == archiveOK else {
            throw ArchiveError(message: String(cString: archive_error_string(a)))
        }

        var entries: [ArchiveEntry] = []
        var entry: OpaquePointer?
        while true {
            let rc = archive_read_next_header(a, &entry)
            if rc == archiveEOF { return (entries, false) }
            if rc < archiveOK { throw ArchiveError(message: String(cString: archive_error_string(a))) }
            guard let entry else { continue }
            if entries.count >= limit { return (entries, true) }

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
}
