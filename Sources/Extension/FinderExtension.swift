import AppKit
import FinderSync

@objc(NewFileFinderExtension)
final class NewFileFinderExtension: FIFinderSync {
    override init() {
        super.init()
        let controller = FIFinderSyncController.default()
        var roots: Set<URL> = [URL(fileURLWithPath: "/")]
        if let home = NewFileFinderExtension.realHomeDirectory {
            roots.insert(home)
        }
        if let volumes = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: nil
        ) {
            roots.formUnion(volumes)
        }
        controller.directoryURLs = roots
        DebugLog.write("init: monitoring \(controller.directoryURLs.count) roots")
    }

    static var realHomeDirectory: URL? {
        guard let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        DebugLog.write("menu request: kind=\(menuKind.rawValue) "
            + "target=\(FIFinderSyncController.default().targetedURL()?.path ?? "nil")")
        let menu = NSMenu(title: "")
        for kind in NewFileKind.allCases {
            let item = NSMenuItem(
                title: kind.menuTitle,
                action: #selector(createFile(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = NewFileKind.allCases.firstIndex(of: kind) ?? 0
            menu.addItem(item)
        }
        return menu
    }

    @objc private func createFile(_ sender: NSMenuItem) {
        let kinds = NewFileKind.allCases
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        let kind = kinds[sender.tag]
        let directory = destinationDirectory()

        do {
            let url = try FileCreator.create(kind, in: directory)
            DebugLog.write("created directly in \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        } catch {
            // A Finder extension always runs sandboxed and may only write inside its
            // own container, so the real work is handed over to the main app.
            DebugLog.write("direct write blocked (\(error.localizedDescription)); delegating")
        }

        delegateToHostApp(kind: kind, directory: directory)
    }

    private func delegateToHostApp(kind: NewFileKind, directory: URL) {
        var components = URLComponents()
        components.scheme = "newfile-create"
        components.host = "create"
        components.queryItems = [
            URLQueryItem(name: "kind", value: kind.requestValue),
            URLQueryItem(name: "dir", value: directory.path),
        ]
        guard let requestURL = components.url else {
            DebugLog.write("delegation failed: bad request url")
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = false

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.timurgizatullin.newfile"
        ) else {
            DebugLog.write("delegation failed: host app not found")
            NSWorkspace.shared.open(requestURL)
            return
        }

        NSWorkspace.shared.open(
            [requestURL],
            withApplicationAt: appURL,
            configuration: configuration
        ) { _, error in
            DebugLog.write("delegated: \(error.map(String.init(describing:)) ?? "ok")")
        }
    }

    /// Folder the new file should land in.
    /// Right-clicking a folder creates the file inside it; right-clicking a file
    /// creates it next to that file; right-clicking empty space uses the folder.
    private func destinationDirectory() -> URL {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs(), !selected.isEmpty {
            let first = selected[0]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return first
            }
            return first.deletingLastPathComponent()
        }
        return controller.targetedURL()
            ?? Self.realHomeDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }
}
