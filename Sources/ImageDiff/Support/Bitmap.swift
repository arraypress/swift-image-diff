//
//  Bitmap.swift
//  ImageDiff
//
//  Decoding two images into one comparable form.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Raw RGBA8 pixels in a known colour space.
struct Bitmap {
    let width: Int
    let height: Int
    /// Four bytes per pixel, row-major, no padding.
    let pixels: [UInt8]

    var count: Int { width * height }
}

enum Decoder {

    /// The largest image this will hold two copies of: 100 megapixels, which
    /// is 400 MB per bitmap at RGBA8. Beyond that the honest answer is a
    /// refusal naming the arithmetic, not a machine that stops responding.
    static let pixelLimit = 100_000_000

    /// Decodes an image into RGBA8 in sRGB.
    ///
    /// Redrawn rather than read straight out of the file, on purpose. Two
    /// screenshots of the same window can arrive as 8-bit sRGB and 16-bit
    /// Display P3, and comparing those byte-for-byte finds a difference in
    /// every pixel while the pictures are identical. Normalising both through
    /// one context is what makes the comparison mean anything.
    static func bitmap(from url: URL) throws -> Bitmap {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DiffError.unreadable(url.path)
        }
        return try bitmap(from: image)
    }

    static func bitmap(from image: CGImage) throws -> Bitmap {
        let width = image.width, height = image.height
        guard width * height <= pixelLimit else {
            throw DiffError.tooLarge(pixels: width * height)
        }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Premultiplied last: the only 8-bit RGBA layout CGBitmapContext
        // supports on every Apple platform. Unpremultiplied is rejected at
        // context creation, which is a runtime nil rather than a compile error.
        guard let context = pixels.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress,
                      width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }) else {
            throw DiffError.unreadable("could not build a comparison bitmap")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return Bitmap(width: width, height: height, pixels: pixels)
    }

    /// Writes RGBA8 pixels out as a PNG.
    static func write(_ bitmap: Bitmap, to url: URL) throws {
        var pixels = bitmap.pixels
        guard let context = pixels.withUnsafeMutableBytes({ raw in
            CGContext(data: raw.baseAddress,
                      width: bitmap.width, height: bitmap.height,
                      bitsPerComponent: 8, bytesPerRow: bitmap.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        }), let image = context.makeImage() else {
            throw DiffError.cannotWrite(url.path)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw DiffError.cannotWrite(url.path)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw DiffError.cannotWrite(url.path)
        }
    }
}
