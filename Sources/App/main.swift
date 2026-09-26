import AppKit
import Carbon.HIToolbox
import FinderSync
import ServiceManagement

/// The app is a small background agent: it lives in the menu bar, does the actual
/// file writing for the (sandboxed) Finder extension and hosts the settings window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?
    private var createSubmenuItem: NSMenuItem?
    private var hotKeyRefs: [EventHotKeyRef?] = []

    private let launchAtLoginToggle = NSButton(
        checkboxWithTitle: "Запускать при входе в систему",
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField(labelWithString: "")

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        DebugLog.write("app: didFinishLaunching (pid \(ProcessInfo.processInfo.processIdentifier))")
        NSApplication.shared.servicesProvider = self
        buildMainMenu()
        buildStatusItem()
        registerHotKeys()
        Updater.shared.scheduleAutomaticCheck()
        if CommandLine.arguments.contains("--check-updates") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Updater.shared.checkInteractively()
            }
        }
    }

    // MARK: - Finder Services (work in iCloud / File Provider folders too)

    @objc func createTextDocument(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        performService(.text, pasteboard: pasteboard, error: error)
    }

    @objc func createWordDocument(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        performService(.word, pasteboard: pasteboard, error: error)
    }

    @objc func createExcelWorkbook(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        performService(.excel, pasteboard: pasteboard, error: error)
    }

    private func performService(
        _ kind: NewFileKind,
        pasteboard: NSPasteboard,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        DebugLog.write("service \(kind.requestValue): received \(urls.map(\.path))")

        // When the service is invoked on empty space (the desktop, an empty folder)
        // Finder hands over nothing, so ask Finder for the folder in focus instead.
        guard let directory = Self.destination(for: urls) ?? Self.frontFinderFolder() else {
            DebugLog.write("service: could not determine destination folder")
            error.pointee = "Не удалось определить папку. Попробуй выбрать папку в Finder." as NSString
            return
        }

        do {
            let url = try FileCreator.create(kind, in: directory)
            DebugLog.write("service created \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch let failure {
            DebugLog.write("service failed: \(failure.localizedDescription)")
            error.pointee = failure.localizedDescription as NSString
        }
    }

    /// Finder hands over the folder the user clicked on (or the parent folder of a
    /// selected file); the desktop itself arrives as a folder URL as well.
    static func destination(for urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return first
        }
        return first.deletingLastPathComponent()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DebugLog.write("app: reopen event")
        showWindow()
        return true
    }

    // MARK: - Requests from the Finder extension

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(request: url) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for name in filenames {
            if let url = URL(string: name) { handle(request: url) }
        }
    }

    private func handle(request url: URL) {
        DebugLog.write("app: request \(url.absoluteString)")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "newfile-create",
              let kindValue = components.queryItems?.first(where: { $0.name == "kind" })?.value,
              let kind = NewFileKind(requestValue: kindValue),
              let path = components.queryItems?.first(where: { $0.name == "dir" })?.value
        else {
            DebugLog.write("app: unparsable request")
            return
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            let fileURL = try FileCreator.create(kind, in: directory)
            DebugLog.write("app: created \(fileURL.path)")
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } catch {
            DebugLog.write("app: failed \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Не удалось создать файл"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "doc.badge.plus",
                accessibilityDescription: "Новый файл"
            )
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Новый файл"
        }

        let menu = NSMenu()

        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        statusMenuItem = status

        menu.addItem(.separator())

        let createSubmenu = NSMenu()
        for (index, kind) in NewFileKind.allCases.enumerated() {
            let subItem = NSMenuItem(
                title: kind.menuTitle,
                action: #selector(createInFrontFolder(_:)),
                keyEquivalent: "\(index + 1)"
            )
            subItem.keyEquivalentModifierMask = [.control, .option, .command]
            subItem.target = self
            subItem.tag = NewFileKind.allCases.firstIndex(of: kind) ?? 0
            createSubmenu.addItem(subItem)
        }
        let createItem = NSMenuItem(
            title: "Создать в открытой папке Finder",
            action: nil,
            keyEquivalent: ""
        )
        createItem.submenu = createSubmenu
        createSubmenuItem = createItem
        menu.addItem(createItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Настройки…",
            action: #selector(showWindow),
            keyEquivalent: ""
        )
        settings.target = self
        menu.addItem(settings)

        let autoStart = NSMenuItem(
            title: "Запускать при входе",
            action: #selector(toggleLaunchAtLoginFromMenu),
            keyEquivalent: ""
        )
        autoStart.target = self
        menu.addItem(autoStart)
        launchAtLoginMenuItem = autoStart

        menu.addItem(.separator())

        let versionItem = NSMenuItem(
            title: "Версия \(Updater.shared.currentVersion)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let updatesItem = NSMenuItem(
            title: "Проверить обновления…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Выход",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApplication.shared
        menu.addItem(quit)

        item.menu = menu
        menu.delegate = self
        statusItem = item
        refresh()
    }

    // MARK: - Global hot keys

    private func registerHotKeys() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            let index = Int(hotKeyID.id)
            DispatchQueue.main.async {
                (NSApplication.shared.delegate as? AppDelegate)?.createFromHotKey(index: index)
            }
            return noErr
        }
        InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, nil)

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let keyCodes = [Int(kVK_ANSI_1), Int(kVK_ANSI_2), Int(kVK_ANSI_3)]
        for (index, keyCode) in keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4E46_4C31), id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                UInt32(keyCode),
                modifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr {
                hotKeyRefs.append(ref)
                DebugLog.write("hotkey \(index + 1) registered")
            } else {
                DebugLog.write("hotkey \(index + 1) failed: \(status)")
            }
        }
    }

    private func createFromHotKey(index: Int) {
        let kinds = NewFileKind.allCases
        guard index >= 1, index <= kinds.count else { return }
        createInFrontFolder(kind: kinds[index - 1])
    }

    /// Menu bar fallback for folders where Finder extensions do not work at all —
    /// iCloud Drive, the synced desktop, Documents, other cloud providers.
    @objc private func createInFrontFolder(_ sender: NSMenuItem) {
        let kinds = NewFileKind.allCases
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        createInFrontFolder(kind: kinds[sender.tag])
    }

    private func createInFrontFolder(kind: NewFileKind) {
        guard let directory = Self.frontFinderFolder() else {
            let alert = NSAlert()
            alert.messageText = "Не удалось определить папку"
            alert.informativeText = "Открой нужную папку в Finder и разреши приложению "
                + "управлять Finder, когда система об этом спросит."
            alert.alertStyle = .warning
            alert.runModal()
            return
        }

        do {
            let url = try FileCreator.create(kind, in: directory)
            DebugLog.write("menu bar: created \(url.path)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch let failure {
            DebugLog.write("menu bar: failed \(failure.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Не удалось создать файл"
            alert.informativeText = failure.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Current folder of the frontmost Finder window (or the desktop).
    static func frontFinderFolder() -> URL? {
        let source = """
        tell application "Finder"
            return POSIX path of (insertion location as alias)
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            DebugLog.write("menu bar: applescript error \(errorInfo)")
            return nil
        }
        guard let path = result.stringValue, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Скрыть",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    // MARK: - Settings window

    @objc private func showWindow() {
        DebugLog.write("app: showWindow")
        if window == nil { buildWindow() }
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Новый файл"
        window.center()
        window.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "Создание файлов в контекстном меню Finder")
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let hint = NSTextField(
            wrappingLabelWithString: "Локальные папки: правый клик — три пункта прямо в меню. "
                + "Любые папки, включая iCloud, рабочий стол и «Документы»: правый клик по папке "
                + "или файлу → Службы → «Создать …». Пустая iCloud-папка: иконка в строке меню → "
                + "«Создать в открытой папке Finder». Новый файл сразу выделяется в Finder."
        )
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)

        statusLabel.font = .systemFont(ofSize: 13)

        let enableButton = NSButton(
            title: "Настройки расширений",
            target: self,
            action: #selector(openExtensionSettings)
        )
        let refreshButton = NSButton(
            title: "Проверить",
            target: self,
            action: #selector(refresh)
        )

        launchAtLoginToggle.target = self
        launchAtLoginToggle.action = #selector(toggleLaunchAtLoginFromToggle)

        let buttonRow = NSStackView(views: [enableButton, refreshButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8

        let stack = NSStackView(views: [
            title,
            hint,
            statusLabel,
            launchAtLoginToggle,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            hint.widthAnchor.constraint(equalToConstant: 440),
        ])

        self.window = window
    }

    // MARK: - State

    @objc private func refresh() {
        let enabled = FIFinderSyncController.isExtensionEnabled
        statusLabel.stringValue = enabled
            ? "Расширение включено — пункты уже доступны в Finder."
            : "Расширение выключено — включи его в системных настройках."
        statusLabel.textColor = enabled ? .systemGreen : .systemOrange

        let loginEnabled = SMAppService.mainApp.status == .enabled
        launchAtLoginToggle.state = loginEnabled ? .on : .off
        statusMenuItem?.title = enabled ? "Расширение включено" : "Расширение выключено"
        launchAtLoginMenuItem?.state = loginEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLoginFromToggle() {
        applyLaunchAtLogin(launchAtLoginToggle.state == .on)
    }

    @objc private func toggleLaunchAtLoginFromMenu() {
        applyLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DebugLog.write("app: login item error \(error)")
        }
        refresh()
    }

    @objc private func checkForUpdates() {
        Updater.shared.checkInteractively()
    }

    @objc private func openExtensionSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences",
            "x-apple.systempreferences:com.apple.preferences.extensions",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Shows the folder the next file will land in, so the menu bar stays predictable.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu == statusItem?.menu else { return }
        refresh()
        if let folder = AppDelegate.frontFinderFolder() {
            createSubmenuItem?.title = "Создать в папке «\(folder.lastPathComponent)»"
        } else {
            createSubmenuItem?.title = "Создать в открытой папке Finder"
        }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
