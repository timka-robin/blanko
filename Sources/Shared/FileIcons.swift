import AppKit
import UniformTypeIdentifiers

extension BlankoKind {
    /// The icon macOS associates with this file type — the real Word/Excel icons
    /// when those applications are installed, the generic document icon otherwise.
    func systemIcon(pointSize: CGFloat = 16) -> NSImage? {
        let type = UTType(filenameExtension: fileExtension) ?? .data
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }
}
