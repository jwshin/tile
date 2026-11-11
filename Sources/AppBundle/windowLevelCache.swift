import CoreGraphics
import Foundation

@MainActor
private var cache: [UInt32: MacOsWindowLevel] = [:]

@MainActor
func invalidateWindowLevelCache() {
    cache.removeAll()
}

@MainActor
func getWindowLevel(for windowId: UInt32) -> MacOsWindowLevel? {
    if let existing = cache[windowId] { return existing }

    var result: [UInt32: MacOsWindowLevel] = [:]
    let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
    guard let cfArray = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [CFDictionary] else { return nil }
    for elem in cfArray {
        let dict = elem as NSDictionary
        guard let windowLayer = (dict[kCGWindowLayer] as? NSNumber)?.intValue,
            let id = (dict[kCGWindowNumber] as? NSNumber)?.uint32Value
        else { continue }
        result[id] = .new(windowLevel: windowLayer)
    }
    cache = result
    return result[windowId]
}

enum MacOsWindowLevel: Sendable, Equatable {
    case normalWindow
    case alwaysOnTopWindow
    case unknown(windowLevel: Int)

    static func new(windowLevel: Int) -> MacOsWindowLevel {
        switch windowLevel {
        case 0: .normalWindow
        case 3: .alwaysOnTopWindow
        default: .unknown(windowLevel: windowLevel)
        }
    }

    static func fromJson(_ json: Json) -> MacOsWindowLevel? {
        switch json {
        case .string("normalWindow"): .normalWindow
        case .string("alwaysOnTopWindow"): .alwaysOnTopWindow
        case .int(let int): .new(windowLevel: Int(exactly: int).orDie())
        default: nil
        }
    }
}
