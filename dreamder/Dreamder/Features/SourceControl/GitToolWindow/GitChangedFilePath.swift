import Foundation

extension GitChangedFile {
    func gitRelativeDirectory(from root: URL) -> String {
        var rootPath = root.path(percentEncoded: false)
        while rootPath.hasSuffix("/") {
            rootPath.removeLast()
        }
        let directory = (fileURL.path(percentEncoded: false) as NSString).deletingLastPathComponent
        guard directory.hasPrefix(rootPath + "/") else {
            return ""
        }
        return String(directory.dropFirst(rootPath.count + 1))
    }
}
