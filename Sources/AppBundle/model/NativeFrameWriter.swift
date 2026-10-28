import Foundation

/// Runs on the app's AX thread. A queued frame must not outlive its permission to resize.
enum NativeFrameWriter {
    static func apply(
        position: CGPoint?, size: CGSize?, fullscreen: () -> Bool?, checkCancellation: () throws -> Void,
        writeSize: (CGSize) -> Bool, writePosition: (CGPoint) -> Bool, readSize: () -> CGSize?
    ) throws -> CGSize? {
        func allowed() throws -> Bool {
            try checkCancellation()
            let result = fullscreen() == false
            try checkCancellation()
            return result
        }
        // Keep the native size/position/size order, checking before each individual mutation.
        if let size {
            guard try allowed() else { return nil }
            _ = writeSize(size)
        }
        if let position {
            guard try allowed() else { return nil }
            _ = writePosition(position)
        }
        guard let size, try allowed(), writeSize(size) else { return nil }
        try checkCancellation()
        return readSize()
    }
}
