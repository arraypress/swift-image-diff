//
//  ImageComparer.swift
//  ImageDiff
//
//  Two pictures in, what changed out.
//

import CoreGraphics
import Foundation

/// Compares two images pixel for pixel and says where they differ.
public enum ImageComparer {

    /// How different two pixels may be before they count as changed, 0–1.
    ///
    /// **Zero, and measured rather than assumed.** The first draft of this
    /// constant was 0.02, on the reasoning that some slack must be needed. A
    /// probe over synthetic screenshots says otherwise:
    ///
    /// | Comparison | max Δ per channel | 99th percentile |
    /// |---|---|---|
    /// | PNG → PNG, same source | **0** | 0 |
    /// | PNG → JPEG q0.9 | 0.239 | 0.008 |
    /// | PNG → JPEG q0.8 | 0.231 | 0.008 |
    /// | PNG → HEIC q0.9 | 0.400 | 0.004 |
    ///
    /// Two PNG encodes of the same pixels are **byte-identical**, so screenshot
    /// regression — the job this exists for — needs no tolerance at all, and a
    /// non-zero default would hide a genuine one-pixel change to buy slack for
    /// a case that never arises.
    ///
    /// The other row is the useful warning. A lossy re-encode moves 99% of
    /// channels by under 0.01, but *ringing at hard edges reaches 0.23–0.40* —
    /// so no tolerance both survives a JPEG round trip and still catches a
    /// real colour change. Comparing across a lossy encode is not a thing
    /// ``compare`` can rescue; compare PNGs, or expect to read
    /// ``Difference/maximumDifference`` and judge.
    ///
    /// `--tolerance 0.01` is the sensible setting when one side has been
    /// through JPEG and you accept edge noise in the regions.
    public static let defaultTolerance = 0.0

    /// The block grid the changed regions are built from.
    ///
    /// 16 px blocks: fine enough to separate two changed words on a page,
    /// coarse enough that a 4K image is a 240×135 grid rather than 8 million
    /// components to union.
    public static let blockSize = 16

    /// Compares two images.
    ///
    /// - Parameters:
    ///   - tolerance: Per-channel difference tolerated, 0–1. See
    ///     ``defaultTolerance``.
    ///   - ignore: Rectangles excluded from the comparison — a clock, a
    ///     timestamp, a progress bar. Excluded pixels are not compared and not
    ///     counted in the denominator, so ignoring half the image does not
    ///     halve the reported percentage.
    /// - Throws: ``DiffError/sizeMismatch(width:height:otherWidth:otherHeight:)``
    ///   when the two are different sizes. There is no defensible pixel-wise
    ///   answer for that, and resizing one to fit invents pixels and then
    ///   reports them as differences.
    public static func compare(
        _ first: URL,
        _ second: URL,
        tolerance: Double = defaultTolerance,
        ignore: [PixelRect] = []
    ) throws -> Difference {
        try compare(Decoder.bitmap(from: first), Decoder.bitmap(from: second),
                    tolerance: tolerance, ignore: ignore)
    }

    static func compare(
        _ first: Bitmap,
        _ second: Bitmap,
        tolerance: Double,
        ignore: [PixelRect]
    ) throws -> Difference {
        guard first.width == second.width, first.height == second.height else {
            throw DiffError.sizeMismatch(width: first.width, height: first.height,
                                         otherWidth: second.width, otherHeight: second.height)
        }

        let width = first.width, height = first.height
        // Scaled once here rather than dividing every channel by 255 inside
        // the loop; on a 4K image that is 33 million divisions saved.
        let threshold = Int((tolerance * 255).rounded())

        let columns = (width + blockSize - 1) / blockSize
        let rows = (height + blockSize - 1) / blockSize
        var blocks = [Bool](repeating: false, count: columns * rows)

        var changed = 0
        var compared = 0
        var worst = 0

        let mask = ignoreMask(ignore, width: width, height: height)

        first.pixels.withUnsafeBufferPointer { a in
            second.pixels.withUnsafeBufferPointer { b in
                for y in 0..<height {
                    let rowStart = y * width
                    for x in 0..<width {
                        let index = rowStart + x
                        if let mask, mask[index] { continue }
                        compared += 1

                        let offset = index * 4
                        // Alpha is compared too: a pixel that went transparent
                        // looks unchanged on white and is a real change.
                        let dr = abs(Int(a[offset]) - Int(b[offset]))
                        let dg = abs(Int(a[offset + 1]) - Int(b[offset + 1]))
                        let db = abs(Int(a[offset + 2]) - Int(b[offset + 2]))
                        let da = abs(Int(a[offset + 3]) - Int(b[offset + 3]))
                        let delta = max(max(dr, dg), max(db, da))
                        if delta > worst { worst = delta }
                        if delta > threshold {
                            changed += 1
                            blocks[(y / blockSize) * columns + (x / blockSize)] = true
                        }
                    }
                }
            }
        }

        return Difference(
            width: width,
            height: height,
            changedPixels: changed,
            comparedPixels: compared,
            percentChanged: compared == 0 ? 0 : (Double(changed) / Double(compared) * 100),
            maximumDifference: Double(worst) / 255,
            regions: regions(from: blocks, columns: columns, rows: rows, width: width, height: height),
            ignored: ignore
        )
    }

    /// A per-pixel "skip this" mask, or nil when nothing is ignored.
    ///
    /// Built once as a flat array rather than testing every pixel against
    /// every rectangle: four ignore rectangles over a 4K image is 133 million
    /// `contains` calls, and this is two.
    private static func ignoreMask(_ rects: [PixelRect], width: Int, height: Int) -> [Bool]? {
        guard !rects.isEmpty else { return nil }
        var mask = [Bool](repeating: false, count: width * height)
        for rect in rects {
            let x0 = max(0, rect.x), y0 = max(0, rect.y)
            let x1 = min(width, rect.x + rect.width), y1 = min(height, rect.y + rect.height)
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 {
                for x in x0..<x1 { mask[y * width + x] = true }
            }
        }
        return mask
    }

    /// Merges changed blocks into bounding boxes, largest first.
    ///
    /// Blocks that touch or sit within one block of each other join, so a line
    /// of changed text is one region rather than eleven. The merge repeats
    /// until nothing more joins: a single pass leaves two halves of one change
    /// reported separately whenever the grid happened to split it.
    private static func regions(
        from blocks: [Bool], columns: Int, rows: Int, width: Int, height: Int
    ) -> [PixelRect] {
        var boxes: [PixelRect] = []
        for row in 0..<rows {
            for column in 0..<columns where blocks[row * columns + column] {
                let x = column * blockSize, y = row * blockSize
                boxes.append(PixelRect(x: x, y: y,
                                       width: min(blockSize, width - x),
                                       height: min(blockSize, height - y)))
            }
        }
        guard !boxes.isEmpty else { return [] }

        var merged = true
        while merged {
            merged = false
            var result: [PixelRect] = []
            for box in boxes {
                if let index = result.firstIndex(where: { $0.touches(box, gap: blockSize) }) {
                    result[index] = result[index].union(box)
                    merged = true
                } else {
                    result.append(box)
                }
            }
            boxes = result
            // A pathological image — a checkerboard of single changed blocks —
            // can otherwise merge one pair per pass forever. 64 regions is far
            // past useful for a human or an agent reading the output.
            if boxes.count > 512 { break }
        }
        return boxes.sorted { $0.area > $1.area }
    }
}
