import Foundation

/// Looks a string up in the bundle that contains this code: the app, the Finder
/// extension or the installer, whichever process is running.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}
