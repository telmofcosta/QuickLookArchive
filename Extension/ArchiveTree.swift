import Foundation

final class TreeNode {
    let name: String
    var isDirectory: Bool
    var size: Int64 = 0
    var modified: Date?
    private(set) var children: [TreeNode] = []
    private var lookup: [String: TreeNode] = [:]

    init(name: String, isDirectory: Bool) {
        self.name = name
        self.isDirectory = isDirectory
    }

    /// Builds a tree from flat archive paths. Folders missing from the archive are created implicitly.
    static func build(from entries: [ArchiveEntry]) -> TreeNode {
        let root = TreeNode(name: "", isDirectory: true)
        for entry in entries {
            let parts = entry.path.split(separator: "/").filter { $0 != "." }.map(String.init)
            guard !parts.isEmpty else { continue }

            var node = root
            for (i, part) in parts.enumerated() {
                let isLast = i == parts.count - 1
                let child = node.lookup[part] ?? {
                    let c = TreeNode(name: part, isDirectory: !isLast || entry.isDirectory)
                    node.lookup[part] = c
                    node.children.append(c)
                    return c
                }()
                if isLast {
                    child.isDirectory = entry.isDirectory
                    child.size = entry.size
                    child.modified = entry.modified
                }
                node = child
            }
        }
        root.sort()
        return root
    }

    private func sort() {
        children.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        children.forEach { $0.sort() }
    }
}
