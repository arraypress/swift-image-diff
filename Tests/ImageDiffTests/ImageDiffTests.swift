//
//  ImageDiffTests.swift
//  ImageDiff
//
//  Synthetic images with a known number of changed pixels in known places,
//  so the answer can be asserted rather than looked at.
//

import CoreGraphics
import Foundation
import XCTest
@testable import ImageDiff

/// A flat canvas with rectangles painted into it.
private func canvas(_ width: Int, _ height: Int, base: (UInt8, UInt8, UInt8) = (255, 255, 255)) -> Bitmap {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        pixels[index] = base.0; pixels[index + 1] = base.1
        pixels[index + 2] = base.2; pixels[index + 3] = 255
    }
    return Bitmap(width: width, height: height, pixels: pixels)
}

private func painting(_ bitmap: Bitmap, _ rect: PixelRect, _ color: (UInt8, UInt8, UInt8, UInt8)) -> Bitmap {
    var pixels = bitmap.pixels
    for y in rect.y..<(rect.y + rect.height) {
        for x in rect.x..<(rect.x + rect.width) {
            let index = (y * bitmap.width + x) * 4
            pixels[index] = color.0; pixels[index + 1] = color.1
            pixels[index + 2] = color.2; pixels[index + 3] = color.3
        }
    }
    return Bitmap(width: bitmap.width, height: bitmap.height, pixels: pixels)
}

final class ComparisonTests: XCTestCase {

    func testIdenticalImagesAreIdentical() throws {
        let image = canvas(100, 100)
        let result = try ImageComparer.compare(image, image, tolerance: 0, ignore: [])
        XCTAssertTrue(result.isIdentical)
        XCTAssertEqual(result.changedPixels, 0)
        XCTAssertEqual(result.percentChanged, 0)
        XCTAssertTrue(result.regions.isEmpty)
    }

    func testTheChangedPixelCountIsExact() throws {
        let before = canvas(100, 100)
        let after = painting(before, PixelRect(x: 10, y: 10, width: 20, height: 5), (255, 0, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [])
        XCTAssertEqual(result.changedPixels, 100)
        XCTAssertEqual(result.comparedPixels, 10_000)
        XCTAssertEqual(result.percentChanged, 1.0, accuracy: 0.0001)
    }

    func testTheRegionCoversTheChange() throws {
        let before = canvas(200, 200)
        let after = painting(before, PixelRect(x: 50, y: 60, width: 30, height: 20), (0, 0, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [])

        XCTAssertEqual(result.regions.count, 1)
        let box = try XCTUnwrap(result.regions.first)
        // The box comes off a 16px grid, so it is at least the change and at
        // most one block wider on each side. Asserting containment rather than
        // exact bounds is the honest test of a deliberately coarse answer.
        XCTAssertLessThanOrEqual(box.x, 50)
        XCTAssertLessThanOrEqual(box.y, 60)
        XCTAssertGreaterThanOrEqual(box.x + box.width, 80)
        XCTAssertGreaterThanOrEqual(box.y + box.height, 80)
    }

    func testTwoDistantChangesAreTwoRegions() throws {
        let before = canvas(400, 400)
        var after = painting(before, PixelRect(x: 10, y: 10, width: 20, height: 20), (255, 0, 0, 255))
        after = painting(after, PixelRect(x: 300, y: 300, width: 20, height: 20), (0, 255, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [])
        XCTAssertEqual(result.regions.count, 2)
        // Largest first.
        XCTAssertGreaterThanOrEqual(result.regions[0].area, result.regions[1].area)
    }

    func testAdjacentBlocksMergeIntoOneRegion() throws {
        // A line of changed text spans many blocks and is one change.
        let before = canvas(400, 100)
        let after = painting(before, PixelRect(x: 20, y: 40, width: 300, height: 12), (0, 0, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [])
        XCTAssertEqual(result.regions.count, 1)
    }

    func testToleranceSuppressesSmallDifferences() throws {
        let before = canvas(50, 50, base: (200, 200, 200))
        let after = canvas(50, 50, base: (202, 200, 200))   // 2/255 = 0.0078

        XCTAssertEqual(try ImageComparer.compare(before, after, tolerance: 0, ignore: []).changedPixels, 2_500)
        XCTAssertEqual(try ImageComparer.compare(before, after, tolerance: 0.01, ignore: []).changedPixels, 0)
    }

    func testTheWorstDifferenceIsReported() throws {
        // The number that says whether "1% changed" is a real change or noise
        // sitting just over the line.
        let before = canvas(50, 50, base: (0, 0, 0))
        let after = painting(before, PixelRect(x: 0, y: 0, width: 1, height: 1), (255, 255, 255, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [])
        XCTAssertEqual(result.maximumDifference, 1.0, accuracy: 0.0001)
    }

    func testAlphaCountsAsAChange() throws {
        // A pixel that went transparent looks unchanged over white and is a
        // real change.
        let before = canvas(20, 20)
        let after = painting(before, PixelRect(x: 0, y: 0, width: 5, height: 5), (255, 255, 255, 0))
        XCTAssertEqual(try ImageComparer.compare(before, after, tolerance: 0, ignore: []).changedPixels, 25)
    }

    func testDifferentSizesAreRefusedNotResized() throws {
        // Resizing one to fit invents pixels and then reports them as changes.
        XCTAssertThrowsError(try ImageComparer.compare(canvas(100, 100), canvas(100, 101),
                                                       tolerance: 0, ignore: [])) { error in
            guard case DiffError.sizeMismatch = error else {
                return XCTFail("expected a size mismatch, got \(error)")
            }
        }
    }
}

final class IgnoreTests: XCTestCase {

    func testAnIgnoredRegionIsNotCounted() throws {
        let before = canvas(100, 100)
        let after = painting(before, PixelRect(x: 0, y: 0, width: 10, height: 10), (0, 0, 0, 255))
        let clock = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let result = try ImageComparer.compare(before, after, tolerance: 0, ignore: [clock])
        XCTAssertTrue(result.isIdentical)
    }

    func testIgnoredPixelsLeaveTheDenominator() throws {
        // Ignoring half the image must not halve the reported percentage —
        // the question is "what fraction of what I looked at changed".
        let before = canvas(100, 100)
        let after = painting(before, PixelRect(x: 50, y: 0, width: 50, height: 100), (0, 0, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0,
                                               ignore: [PixelRect(x: 0, y: 0, width: 50, height: 100)])
        XCTAssertEqual(result.comparedPixels, 5_000)
        XCTAssertEqual(result.changedPixels, 5_000)
        XCTAssertEqual(result.percentChanged, 100, accuracy: 0.0001)
    }

    func testAnIgnoreRectangleOffTheEdgeIsClipped() throws {
        let before = canvas(50, 50)
        let after = painting(before, PixelRect(x: 0, y: 0, width: 10, height: 10), (0, 0, 0, 255))
        let result = try ImageComparer.compare(before, after, tolerance: 0,
                                               ignore: [PixelRect(x: -20, y: -20, width: 100, height: 100)])
        XCTAssertEqual(result.comparedPixels, 0)
        XCTAssertEqual(result.percentChanged, 0)
    }
}

final class PixelRectTests: XCTestCase {

    func testUnion() {
        let a = PixelRect(x: 0, y: 0, width: 10, height: 10)
        let b = PixelRect(x: 20, y: 20, width: 10, height: 10)
        XCTAssertEqual(a.union(b), PixelRect(x: 0, y: 0, width: 30, height: 30))
    }

    func testTouchingWithAGap() {
        let a = PixelRect(x: 0, y: 0, width: 16, height: 16)
        let b = PixelRect(x: 32, y: 0, width: 16, height: 16)
        XCTAssertFalse(a.touches(b, gap: 0))
        XCTAssertTrue(a.touches(b, gap: 16))
    }
}

final class OverlayTests: XCTestCase {

    func testTheMaskIsWhereTheChangeIs() {
        let before = canvas(64, 64)
        let after = painting(before, PixelRect(x: 10, y: 10, width: 8, height: 8), (0, 0, 0, 255))
        let mask = Overlay.render(before, after, style: .mask, tolerance: 0, ignore: [])

        func luminance(_ x: Int, _ y: Int) -> UInt8 { mask.pixels[(y * mask.width + x) * 4] }
        XCTAssertEqual(luminance(12, 12), 255)   // inside the change
        XCTAssertEqual(luminance(40, 40), 0)     // outside it
    }

    func testSideBySideIsTwiceAsWide() {
        let before = canvas(30, 20)
        let after = painting(before, PixelRect(x: 0, y: 0, width: 5, height: 5), (0, 0, 0, 255))
        let rendered = Overlay.render(before, after, style: .sideBySide, tolerance: 0, ignore: [])
        XCTAssertEqual(rendered.width, 60)
        XCTAssertEqual(rendered.height, 20)
    }

    func testTintPaintsChangedPixelsRedAtFullStrength() {
        // Blended red over a red button is invisible, which defeats the only
        // purpose the picture has.
        let before = canvas(20, 20, base: (255, 0, 0))
        let after = painting(before, PixelRect(x: 5, y: 5, width: 5, height: 5), (0, 0, 255, 255))
        let tinted = Overlay.render(before, after, style: .tint, tolerance: 0, ignore: [])
        let index = (7 * 20 + 7) * 4
        XCTAssertEqual(tinted.pixels[index], 255)
        XCTAssertEqual(tinted.pixels[index + 1], 40)
        XCTAssertEqual(tinted.pixels[index + 2], 40)
    }
}
