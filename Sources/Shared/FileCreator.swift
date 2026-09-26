import Foundation

enum BlankoKind: CaseIterable {
    case text
    case word
    case excel

    var menuTitle: String {
        switch self {
        case .text: return "Создать текстовый документ"
        case .word: return "Создать документ Word"
        case .excel: return "Создать таблицу Excel"
        }
    }

    var baseName: String {
        switch self {
        case .text: return "Новый текстовый документ"
        case .word: return "Новый документ Word"
        case .excel: return "Новая таблица Excel"
        }
    }

    var fileExtension: String {
        switch self {
        case .text: return "txt"
        case .word: return "docx"
        case .excel: return "xlsx"
        }
    }

    var contents: Data {
        switch self {
        case .text: return FileTemplates.textDocument()
        case .word: return FileTemplates.wordDocument()
        case .excel: return FileTemplates.excelWorkbook()
        }
    }

    var requestValue: String {
        switch self {
        case .text: return "text"
        case .word: return "word"
        case .excel: return "excel"
        }
    }

    init?(requestValue: String) {
        switch requestValue {
        case "text": self = .text
        case "word": self = .word
        case "excel": self = .excel
        default: return nil
        }
    }
}

enum FileCreator {
    /// Creates a new file of the given kind in `directory` and returns its URL.
    /// Existing files are never overwritten: names get a numeric suffix instead.
    @discardableResult
    static func create(_ kind: BlankoKind, in directory: URL) throws -> URL {
        let target = uniqueURL(base: kind.baseName, ext: kind.fileExtension, in: directory)
        do {
            try kind.contents.write(to: target, options: .withoutOverwriting)
        } catch {
            DebugLog.write("write to \(target.path) failed: \(error)")
            throw NSError(
                domain: "Blanko",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Не удалось создать файл в \(directory.path): \(error.localizedDescription)"
                ]
            )
        }
        return target
    }

    static func uniqueURL(base: String, ext: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
