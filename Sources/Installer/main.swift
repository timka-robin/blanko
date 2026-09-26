import AppKit

/// Small installer shipped inside the DMG: shows a window, runs the bundled
/// install script against the bundled copy of Blanko and reports the result.
final class InstallerDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private let statusLabel = NSTextField(labelWithString: "Готов к установке")
    private let logView = NSTextView()
    private let spinner = NSProgressIndicator()
    private let actionButton = NSButton(title: "Установить", target: nil, action: nil)
    private var isInstalling = false
    private var isFinished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - UI

    private func buildMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Завершить",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApplication.shared.mainMenu = mainMenu
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Установить Blanko"
        window.center()
        window.isReleasedWhenClosed = false

        let icon = NSImageView()
        icon.image = NSApplication.shared.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 72).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 72).isActive = true

        let title = NSTextField(labelWithString: "Blanko")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "Создание файлов прямо из меню Finder")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)
        let headline = NSStackView(views: [title, subtitle])
        headline.orientation = .vertical
        headline.alignment = .leading
        headline.spacing = 2

        let header = NSStackView(views: [icon, headline])
        header.orientation = .horizontal
        header.spacing = 14
        header.alignment = .centerY

        let explanation = NSTextField(
            wrappingLabelWithString: "Установщик скопирует Blanko в «Программы», снимет карантин, "
                + "зарегистрирует и включит расширение Finder, а затем запустит приложение. "
                + "Пароль администратора не нужен."
        )
        explanation.textColor = .secondaryLabelColor
        explanation.font = .systemFont(ofSize: 12)
        explanation.preferredMaxLayoutWidth = 500

        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.translatesAutoresizingMaskIntoConstraints = false
        logScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
        logScroll.documentView = logView
        logView.isEditable = false
        logView.drawsBackground = true
        logView.backgroundColor = .textBackgroundColor
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 6, height: 6)
        logView.autoresizingMask = [.width]
        logView.isVerticallyResizable = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        statusLabel.font = .systemFont(ofSize: 12)

        let statusRow = NSStackView(views: [spinner, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 8
        statusRow.alignment = .centerY

        actionButton.target = self
        actionButton.action = #selector(runOrClose)
        actionButton.keyEquivalent = "\r"
        actionButton.bezelStyle = .rounded

        let quitButton = NSButton(title: "Закрыть", target: self, action: #selector(closeWindow))
        quitButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [quitButton, actionButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        let stack = NSStackView(views: [
            header,
            explanation,
            logScroll,
            statusRow,
            buttonRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            explanation.widthAnchor.constraint(equalToConstant: 500),
            logScroll.widthAnchor.constraint(equalToConstant: 520),
        ])

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        self.window = window
    }

    // MARK: - Installing

    @objc private func runOrClose() {
        if isFinished {
            NSApplication.shared.terminate(nil)
            return
        }
        guard !isInstalling else { return }
        install()
    }

    @objc private func closeWindow() {
        NSApplication.shared.terminate(nil)
    }

    private func install() {
        guard let resources = Bundle.main.resourceURL else { return }
        let payload = resources.appendingPathComponent("Blanko.app")
        let script = resources.appendingPathComponent("install.sh")
        guard FileManager.default.fileExists(atPath: payload.path),
              FileManager.default.fileExists(atPath: script.path) else {
            append("Внутри установщика нет Blanko.app или install.sh — похоже, архив повреждён.")
            return
        }

        isInstalling = true
        actionButton.isEnabled = false
        spinner.startAnimation(nil)
        statusLabel.stringValue = "Устанавливаю…"
        append("$ install.sh \(payload.path)\n")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path, payload.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                DispatchQueue.main.async { self?.append(text) }
            }

            var failed = false
            do {
                try process.run()
                process.waitUntilExit()
                failed = process.terminationStatus != 0
            } catch {
                failed = true
                DispatchQueue.main.async { self?.append("Ошибка запуска: \(error.localizedDescription)\n") }
            }
            pipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                guard let self else { return }
                self.isInstalling = false
                self.isFinished = !failed
                self.spinner.stopAnimation(nil)
                self.statusLabel.stringValue = failed
                    ? "Установка не удалась — смотри журнал ниже"
                    : "Готово: Blanko установлен и запущен"
                self.actionButton.title = failed ? "Повторить" : "Закрыть"
                self.actionButton.isEnabled = true
            }
        }
    }

    private func append(_ text: String) {
        logView.textStorage?.append(NSAttributedString(string: text))
        logView.scrollToEndOfDocument(nil)
    }
}

let application = NSApplication.shared
let delegate = InstallerDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
