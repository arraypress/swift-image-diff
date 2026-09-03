//
//  Difference.swift
//  ImageDiff
//

import CoreGraphics
import Foundation

/// A rectangle of the image, in pixels from the top-left.
///
/// Its own type rather than `CGRect` because `CGRect` is floating point and
/// origin-flipped depending on who drew it, and because this one is `Codable`
/// straight into a tool's JSON.
public struct PixelRect: Sendable, Hashable, Codable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Int { width * height }

    /// Whether a pixel lies inside.
    public func contains(x px: Int, y py: Int) -> Bool {
        px >= x && px < x + width && py >= y && py < y + height
    }

    /// The smallest rectangle covering both.
    public func union(_ other: PixelRect) -> PixelRect {
        let minX = Swift.min(x, other.x), minY = Swift.min(y, other.y)
        let maxX = Swift.max(x + width, other.x + other.width)
        let maxY = Swift.max(y + height, other.y + other.height)
        return PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Whether the two touch or overlap, allowing `gap` pixels between them.
    ///
    /// Inclusive at exactly `gap`: with a strict `<`, two changed blocks
    /// separated by precisely one empty block failed to merge, which is the
    /// most common spacing there is — one gap between two words. Caught by a
    /// test rather than by reading it.
    public func touches(_ other: PixelRect, gap: Int) -> Bool {
        x - gap <= other.x + other.width && other.x - gap <= x + width &&
        y - gap <= other.y + other.height && other.y - gap <= y + height
    }
}

/// What changed between two images.
public struct Difference: Sendable, Hashable, Codable {

    public let width: Int
    public let height: Int

    /// Pixels whose difference exceeded the tolerance.
    public let changedPixels: Int

    /// Pixels compared — total, less anything inside an ignored rectangle.
    public let comparedPixels: Int

    /// Changed as a percentage of compared, 0–100.
    public let percentChanged: Double

    /// The largest per-channel difference seen anywhere, 0–1.
    ///
    /// Reported because it is the number that tells you whether a "1.2%
    /// changed" result is a real visual change or compression noise sitting
    /// just over the tolerance.
    public let maximumDifference: Double

    /// Bounding boxes of the changed areas, largest first.
    ///
    /// Coarse by design — these come from a block grid, not from per-pixel
    /// connected components. A box says "look here", and a box that is exact
    /// to the pixel is no more useful for that while costing far more to find.
    public let regions: [PixelRect]

    /// Rectangles that were excluded from the comparison.
    public let ignored: [PixelRect]

    /// Whether anything changed at all.
    public var isIdentical: Bool { changedPixels == 0 }
}
