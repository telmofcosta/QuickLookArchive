import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {
    private let textView = NSTextView()

    override func loadView() {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        view = scroll
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let (entries, truncated) = try ArchiveReader.list(url: url)
        let dates = DateFormatter()
        dates.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = entries.map { e -> String in
            let size = e.isDirectory ? "" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)
            let date = e.modified.map(dates.string(from:)) ?? ""
            return "\(date.padding(toLength: 16, withPad: " ", startingAt: 0))  \(size.padding(toLength: 10, withPad: " ", startingAt: 0))  \(e.path)"
        }
        if truncated { lines.append("… listing truncated") }
        let text = lines.isEmpty ? "(empty archive)" : lines.joined(separator: "\n")

        await MainActor.run { textView.string = text }
    }
}
