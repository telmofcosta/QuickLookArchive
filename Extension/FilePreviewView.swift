import Cocoa
import PDFKit
import UniformTypeIdentifiers

/// Right-hand pane: shows one file's contents as an image, PDF or text, or a short message.
final class FilePreviewView: NSView {
    private let textScroll = NSTextView.scrollableTextView()
    private let imageView = NSImageView()
    private let pdfView = PDFView()
    private let message = NSTextField(wrappingLabelWithString: "")

    private var textView: NSTextView { textScroll.documentView as! NSTextView }
    private var all: [NSView] { [textScroll, imageView, pdfView, message] }

    override init(frame: NSRect) {
        super.init(frame: frame)

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        pdfView.autoScales = true
        message.textColor = .secondaryLabelColor
        message.alignment = .center

        for v in all {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        for v in [textScroll, imageView, pdfView] {
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: leadingAnchor),
                v.trailingAnchor.constraint(equalTo: trailingAnchor),
                v.topAnchor.constraint(equalTo: topAnchor),
                v.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
        ])
        showMessage("Select a file to preview")
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    }

    func showMessage(_ text: String) {
        message.stringValue = text
        display(message)
    }

    /// `truncated` means `data` is only the start of the file.
    func show(data: Data, name: String, truncated: Bool) {
        let type = UTType(filenameExtension: (name as NSString).pathExtension)

        if !truncated, type?.conforms(to: .image) == true, let image = NSImage(data: data) {
            imageView.image = image
            return display(imageView)
        }
        if !truncated, type?.conforms(to: .pdf) == true, let document = PDFDocument(data: data) {
            pdfView.document = document
            return display(pdfView)
        }
        if let text = Self.text(from: data) {
            textView.string = truncated ? text + "\n\n… truncated" : text
            textView.scrollToBeginningOfDocument(nil)
            return display(textScroll)
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        showMessage(truncated ? "Too large to preview" : "No preview for this file type (\(size))")
    }

    private func display(_ shown: NSView) {
        all.forEach { $0.isHidden = $0 !== shown }
    }

    /// Treats data as text unless it contains a NUL byte near the start.
    private static func text(from data: Data) -> String? {
        if data.prefix(8_000).contains(0) { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
