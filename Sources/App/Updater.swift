import AppKit
import CryptoKit
import Foundation

/// Update manifest published on the `release` branch (`update.json`).
struct UpdateManifest: Decodable {
    let version: String
    let url: String
    let sha256: String
    let notes: String?
}

/// Checks the release branch for a newer build and installs it in place.
final class Updater {
    static let shared = Updater()

    /// Raw files of the release branch, with mirrors in case one host is blocked.
    /// `NEWFILE_UPDATE_MANIFEST` overrides this (used for testing the update path).
    private var manifestURLs: [String] {
        if let override = ProcessInfo.processInfo.environment["NEWFILE_UPDATE_MANIFEST"],
           !override.isEmpty {
            return [override]
        }
        return defaultManifestURLs
    }

    private let defaultManifestURLs = [
        "https://raw.githubusercontent.com/timka-robin/newfilemac/release/update.json",
        "https://github.com/timka-robin/newfilemac/raw/release/update.json",
        "https://cdn.jsdelivr.net/gh/timka-robin/newfilemac@release/update.json",
    ]

    /// Skips the confirmation dialogs — `NEWFILE_UPDATE_AUTO=1` for automated checks.
    private var isAutomated: Bool {
        ProcessInfo.processInfo.environment["NEWFILE_UPDATE_AUTO"] == "1"
    }

    private let lastCheckKey = "lastUpdateCheckDate"
    private var isChecking = false

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Self-updating only makes sense for the installed copy.
    var canSelfUpdate: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    // MARK: - Entry points

    /// Silent check, at most once a day, a few seconds after launch.
    func scheduleAutomaticCheck() {
        guard canSelfUpdate else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 20 * 60 * 60 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.check(userInitiated: false)
        }
    }

    /// Menu bar action — always reports something.
    func checkInteractively() {
        guard !isChecking else { return }
        check(userInitiated: true)
    }

    // MARK: - Checking

    private func check(userInitiated: Bool) {
        isChecking = true
        DebugLog.write("updater: check started (version \(currentVersion))")
        fetchManifest { [weak self] manifest in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isChecking = false
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)

                guard let manifest else {
                    DebugLog.write("updater: manifest unavailable")
                    if userInitiated {
                        self.present(
                            title: "Не удалось проверить обновления",
                            text: "Нет связи с GitHub. Попробуй позже."
                        )
                    }
                    return
                }

                DebugLog.write("updater: manifest version \(manifest.version)")
                if self.isNewer(manifest.version, than: self.currentVersion) {
                    self.offer(manifest)
                } else if userInitiated {
                    self.present(
                        title: "Обновлений нет",
                        text: "Установлена последняя версия (\(self.currentVersion))."
                    )
                }
            }
        }
    }

    private func fetchManifest(completion: @escaping (UpdateManifest?) -> Void) {
        var pending = manifestURLs

        func attempt() {
            guard let candidate = pending.first else {
                completion(nil)
                return
            }
            pending.removeFirst()

            guard var components = URLComponents(string: candidate) else {
                attempt()
                return
            }
            components.queryItems = [
                URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))
            ]
            guard let url = components.url else {
                attempt()
                return
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.timeoutInterval = 20

            DebugLog.write("updater: trying \(url.absoluteString)")
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    let nsError = error as NSError
                    DebugLog.write("updater: \(url.host ?? "?") failed "
                        + "\(nsError.domain)/\(nsError.code) \(error.localizedDescription)")
                } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    DebugLog.write("updater: \(url.host ?? "?") HTTP \(http.statusCode)")
                }

                if let data,
                   let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data),
                   !manifest.version.isEmpty,
                   !manifest.sha256.isEmpty {
                    completion(manifest)
                } else {
                    attempt()
                }
            }.resume()
        }

        attempt()
    }

    private func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let old = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(new.count, old.count) {
            let left = index < new.count ? new[index] : 0
            let right = index < old.count ? old[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    // MARK: - Installing

    private func offer(_ manifest: UpdateManifest) {
        if isAutomated {
            DebugLog.write("updater: automatic mode, installing \(manifest.version)")
            download(manifest)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Доступна версия \(manifest.version)"
        var text = "Установлена версия \(currentVersion).\n\n"
        if let notes = manifest.notes, !notes.isEmpty {
            text += notes + "\n\n"
        }
        text += "Скачать и установить обновление?"
        alert.informativeText = text
        alert.addButton(withTitle: "Обновить")
        alert.addButton(withTitle: "Позже")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        download(manifest)
    }

    private func download(_ manifest: UpdateManifest) {
        guard let url = URL(string: manifest.url) else {
            present(title: "Ошибка обновления", text: "В манифесте некорректная ссылка.")
            return
        }

        DebugLog.write("updater: downloading \(manifest.url)")
        if url.isFileURL {
            do {
                let newApp = try unpackAndVerify(manifest: manifest, downloaded: url)
                installAndRestart(newApp: newApp)
            } catch {
                present(title: "Ошибка обновления", text: error.localizedDescription)
            }
            return
        }

        URLSession.shared.downloadTask(with: url) { [weak self] location, _, error in
            guard let self else { return }
            guard let location, error == nil else {
                DispatchQueue.main.async {
                    self.present(
                        title: "Ошибка обновления",
                        text: "Не удалось скачать архив: \(error?.localizedDescription ?? "неизвестная ошибка")"
                    )
                }
                return
            }

            do {
                let newApp = try self.unpackAndVerify(manifest: manifest, downloaded: location)
                DispatchQueue.main.async { self.installAndRestart(newApp: newApp) }
            } catch {
                DebugLog.write("updater: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.present(title: "Ошибка обновления", text: error.localizedDescription)
                }
            }
        }.resume()
    }

    private func unpackAndVerify(manifest: UpdateManifest, downloaded: URL) throws -> URL {
        let data = try Data(contentsOf: downloaded)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.lowercased() == manifest.sha256.lowercased() else {
            throw updateError("Контрольная сумма не совпала — обновление отклонено.")
        }

        let workDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NewFileUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let archive = workDir.appendingPathComponent("NewFile.app.zip")
        try FileManager.default.moveItem(at: downloaded, to: archive)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, workDir.path])

        let newApp = try locateAppBundle(in: workDir)
        DebugLog.write("updater: verified \(newApp.path)")
        return newApp
    }

    /// The release archive keeps NewFile.app at the top level; look a level deeper
    /// as well so archives with a wrapping folder still install.
    private func locateAppBundle(in directory: URL) throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = [directory.appendingPathComponent("NewFile.app")]

        if let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) {
            for entry in entries where entry.pathExtension == "app" {
                candidates.append(entry)
                if let inner = try? fileManager.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: nil
                ) {
                    candidates.append(contentsOf: inner.filter { $0.pathExtension == "app" })
                }
            }
        }

        for candidate in candidates {
            let plistURL = candidate.appendingPathComponent("Contents/Info.plist")
            if let plist = NSDictionary(contentsOf: plistURL),
               plist["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier {
                return candidate
            }
        }
        throw updateError("Скачанный архив не похож на NewFile — установка отменена.")
    }

    private func installAndRestart(newApp: URL) {
        if !isAutomated {
            let alert = NSAlert()
            alert.messageText = "Обновление готово"
            alert.informativeText = "Приложение сейчас перезапустится, чтобы применить обновление."
            alert.addButton(withTitle: "Перезапустить")
            alert.runModal()
        }

        let workDir = newApp.deletingLastPathComponent()
        let scriptURL = workDir.appendingPathComponent("install-update.sh")
        do {
            try installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: scriptURL.path
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [
                scriptURL.path,
                String(ProcessInfo.processInfo.processIdentifier),
                Bundle.main.bundlePath,
                newApp.path,
                workDir.path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            DebugLog.write("updater: installer started, quitting")
            NSApplication.shared.terminate(nil)
        } catch {
            present(title: "Ошибка обновления", text: error.localizedDescription)
        }
    }

    private var installerScript: String {
        """
        #!/bin/sh
        # Waits for the app to quit, swaps the bundle, relaunches. Written by Updater.swift.
        PID="$1"
        APP="$2"
        NEW="$3"
        WORK="$4"

        i=0
        while /bin/kill -0 "$PID" 2>/dev/null; do
            /bin/sleep 0.2
            i=$((i + 1))
            [ "$i" -gt 150 ] && break
        done

        STAGE="${APP}.new"
        OLD="${APP}.old"
        /bin/rm -rf "$STAGE" "$OLD"

        if /usr/bin/ditto "$NEW" "$STAGE"; then
            /usr/bin/xattr -cr "$STAGE"
            if /bin/mv "$APP" "$OLD" 2>/dev/null; then
                /bin/mv "$STAGE" "$APP"
                /bin/rm -rf "$OLD"
            else
                /bin/rm -rf "$STAGE"
            fi
            /usr/bin/open "$APP"
        fi

        /bin/rm -rf "$WORK"
        exit 0
        """
    }

    // MARK: - Helpers

    private func run(_ launchPath: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw updateError("Не удалось распаковать обновление.")
        }
    }

    private func updateError(_ message: String) -> Error {
        NSError(domain: "NewFileUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func present(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
