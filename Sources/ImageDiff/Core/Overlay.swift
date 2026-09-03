//
//  Overlay.swift
//  ImageDiff
//
//  Showing the change, not just counting it.
//

import CoreGraphics
import Foundation

/// Renders what changed as a picture somebody can look at.
public enum Overlay {

    /// How to draw the result.
    public enum Style: String, Sendable, CaseIterable, Codable {
        /// The second image, faded, with changed pixels painted red.
        case tint
        /// Changed pixels white on black — the mask alone.
        case mask
        /// The two images side by side with the changes tinted in the second.
        case sideBySide
    }

    /// Writes a picture of the difference to `url` as PNG.
    ///
    /// - Throws: ``DiffError`` if either image cannot be read or the file
    ///   cannot be written.
    public static func write(
        comparing first: URL,
        with second: URL,
        to url: URL,
        style: Style = .tint,
        tolerance: Double = ImageComparer.defaultTolerance,
        ignore: [PixelRect] = []
    ) throws {
        let a = try Decoder.bitmap(from: first)
        let b = try Decoder.bitmap(from: second)
        guard a.width == b.width, a.height == b.height else {
            throw DiffError.sizeMismatch(width: a.width, height: a.height,
                                         otherWidth: b.width, otherHeight: b.height)
        }
        try Decoder.write(render(a, b, style: style, tolerance: tolerance, ignore: ignore), to: url)
    }

    static func render(
        _ a: Bitmap, _ b: Bitmap, style: Style, tolerance: Double, ignore: [PixelRect]
    ) -> Bitmap {
        let width = a.width, height = a.height
        let threshold = Int((tolerance * 255).rounded())
        let doubleWidth = style == .sideBySide ? width * 2 : width
        var out = [UInt8](repeating: 0, count: doubleWidth * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                let ignored = ignore.contains { $0.contains(x: x, y: y) }

                let dr = abs(Int(a.pixels[index]) - Int(b.pixels[index]))
                let dg = abs(Int(a.pixels[index + 1]) - Int(b.pixels[index + 1]))
                let db = abs(Int(a.pixels[index + 2]) - Int(b.pixels[index + 2]))
                let da = abs(Int(a.pixels[index + 3]) - Int(b.pixels[index + 3]))
                let changed = !ignored && max(max(dr, dg), max(db, da)) > threshold

                let target = (y * doubleWidth + (style == .sideBySide ? x + width : x)) * 4

                switch style {
                case .mask:
                    let value: UInt8 = changed ? 255 : 0
                    out[target] = value; out[target + 1] = value; out[target + 2] = value
                    out[target + 3] = 255

                case .tint, .sideBySide:
                    if changed {
                        // Full-strength red, not a blend: a change tinted 50%
                        // over a red button is invisible, which defeats the
                        // only purpose the picture has.
                        out[target] = 255; out[target + 1] = 40; out[target + 2] = 40
                    } else {
                        // Unchanged pixels are faded towards white so the red
                        // reads at a glance, while the layout stays legible
                        // enough to say WHERE the change is.
                        for channel in 0..<3 {
                            let value = Int(b.pixels[index + channel])
                            out[target + channel] = UInt8(value + (255 - value) * 3 / 5)
                        }
                    }
                    out[target + 3] = 255
                }

                if style == .sideBySide {
                    let left = (y * doubleWidth + x) * 4
                    out[left] = a.pixels[index]
                    out[left + 1] = a.pixels[index + 1]
                    out[left + 2] = a.pixels[index + 2]
                    out[left + 3] = 255
                }
            }
        }
        return Bitmap(width: doubleWidth, height: height, pixels: out)
    }
}
