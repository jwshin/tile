import AppKit
import Foundation

public protocol TileValue {}

extension TileValue {
    @discardableResult
    @inlinable
    public func apply(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @discardableResult
    @inlinable
    public func also(_ block: (Self) -> Void) -> Self {
        block(self)
        return self
    }

    @inlinable public func takeIf(_ predicate: (Self) -> Bool) -> Self? { predicate(self) ? self : nil }

}

extension Int: TileValue {}
extension String: TileValue {}
extension Character: TileValue {}
extension Regex: TileValue {}
extension Array: TileValue {}
extension URL: TileValue {}
extension CGFloat: TileValue {}
extension AXUIElement: TileValue {}
extension CGPoint: TileValue {}
