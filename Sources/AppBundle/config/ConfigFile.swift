import Foundation

let configDotfileName = ".tile.toml"
func findCustomConfigUrl() -> ConfigFile {
    let url =
        FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
    return FileManager.default.fileExists(atPath: url.path) ? .file(url) : .noCustomConfigExists
}

enum ConfigFile {
    case file(URL)
    case noCustomConfigExists
    var urlOrNil: URL? {
        if case .file(let url) = self { return url }
        return nil
    }
}
