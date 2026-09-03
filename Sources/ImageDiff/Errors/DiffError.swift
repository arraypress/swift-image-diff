//
//  DiffError.swift
//  ImageDiff
//

import Foundation

/// What stopped a comparison.
public enum DiffError: Error, LocalizedError, Equatable, Sendable {

    /// The file is not an image this platform can decode.
    case unreadable(String)

    /// The two images are different sizes, so there is no pixel to compare a
    /// pixel with.
    case sizeMismatch(width: Int, height: Int, otherWidth: Int, otherHeight: Int)

    /// An image was too large to hold two copies of in memory.
    case tooLarge(pixels: Int)

    /// The overlay could not be written.
    case cannotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            return "cannot read an image from \(path)"
        case .sizeMismatch(let w, let h, let ow, let oh):
            return """
                different sizes: \(w)×\(h) and \(ow)×\(oh)
                there is no pixel to compare a pixel with; crop or re-render one to match
                """
        case .tooLarge(let pixels):
            return "image is \(pixels) pixels — too large to compare in memory"
        case .cannotWrite(let path):
            return "cannot write \(path)"
        }
    }
}
