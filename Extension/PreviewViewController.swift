import Cocoa
import Quartz
import UniformTypeIdentifiers

class PreviewViewController: NSViewController, QLPreviewingController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let outline = NSOutlineView()
    private let notice = NSTextField(labelWithString: "")
    private var root = TreeNode(name: "", isDirectory: true)

    private let dates: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    override func loadView() {
        for (id, title, width) in [("name", "Name", 320.0), ("size", "Size", 80.0), ("modified", "Modified", 130.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 50
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.usesAlternatingRowBackgroundColors = true
        outline.dataSource = self
        outline.delegate = self

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = outline

        notice.textColor = .secondaryLabelColor
        notice.isHidden = true

        let stack = NSStackView(views: [scroll, notice])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 4, right: 0)
        view = stack
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let (entries, truncated) = try ArchiveReader.list(url: url)
        let tree = TreeNode.build(from: entries)

        await MainActor.run {
            root = tree
            notice.stringValue = "Listing truncated"
            notice.isHidden = !truncated
            outline.reloadData()
            // Collapsed by default; a single root folder is expanded.
            if tree.children.count == 1, tree.children[0].isDirectory {
                outline.expandItem(tree.children[0])
            }
        }
    }

    // MARK: Data source

    private func node(_ item: Any?) -> TreeNode { (item as? TreeNode) ?? root }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(item).children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(item).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? TreeNode)?.isDirectory == true
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode, let id = tableColumn?.identifier else { return nil }

        let cell = outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? makeCell(id)
        switch id.rawValue {
        case "name":
            cell.textField?.stringValue = node.name
            let type = node.isDirectory ? UTType.folder : (UTType(filenameExtension: (node.name as NSString).pathExtension) ?? .data)
            cell.imageView?.image = NSWorkspace.shared.icon(for: type)
        case "size":
            cell.textField?.stringValue = node.isDirectory || node.size < 0 ? "" : ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
        default:
            cell.textField?.stringValue = node.modified.map(dates.string(from:)) ?? ""
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text

        if id.rawValue == "name" {
            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            ])
        } else {
            text.textColor = .secondaryLabelColor
            if id.rawValue == "size" { text.alignment = .right }
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor).isActive = true
        }
        text.trailingAnchor.constraint(equalTo: cell.trailingAnchor).isActive = true
        text.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
        return cell
    }
}
