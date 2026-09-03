# Swift ImageDiff

What changed between two images — as typed values, on device, on any Apple platform.

```swift
import ImageDiff

let result = try ImageComparer.compare(before, after)
result.percentChanged      // 0.958
result.regions             // [128×48 at 240,496, 16×32 at 720,0]
result.maximumDifference   // 0.745

try Overlay.write(comparing: before, with: after, to: diff, style: .tint)
```

## Why

Screenshot regression has no answer on this platform that does not involve a browser,
a service, or a Python dependency tree. This is CoreGraphics: decode both, compare,
report where.

The useful part is not the percentage — it is **where**, and **what to ignore**. A
screenshot with a clock in it differs from itself every minute, and a tool that cannot
be told to skip that rectangle is a tool that always says "changed".

## Installation

```swift
.package(url: "https://github.com/arraypress/swift-image-diff.git", from: "0.1.0")
```

CoreGraphics and ImageIO. No other dependencies.

## The default tolerance is zero, and that is measured

The first draft of this constant was 0.02, on the reasoning that some slack must be
needed. A probe over synthetic screenshots says otherwise:

| Comparison | max Δ per channel | 99th percentile |
|---|---|---|
| PNG → PNG, same source | **0** | 0 |
| PNG → JPEG q0.9 | 0.239 | 0.008 |
| PNG → JPEG q0.8 | 0.231 | 0.008 |
| PNG → HEIC q0.9 | 0.400 | 0.004 |

Two PNG encodes of the same pixels are byte-identical, so screenshot regression — the
job this exists for — needs no tolerance at all, and a non-zero default would hide a
genuine one-pixel change to buy slack for a case that never arises.

The other row is the warning worth keeping. A lossy re-encode moves 99% of channels by
under 0.01, but **ringing at hard edges reaches 0.23–0.40** — so no tolerance both
survives a JPEG round trip and still catches a real colour change. Compare PNGs, or
read `maximumDifference` and judge.

## What it does with the awkward cases

**Different sizes are refused.** There is no pixel to compare a pixel with, and resizing
one to fit invents pixels and then reports them as differences.

**Both images are redrawn through one sRGB context** before comparing. Two screenshots
of the same window can arrive as 8-bit sRGB and 16-bit Display P3; comparing those
byte-for-byte finds a difference in every pixel while the pictures are identical.

**Ignored rectangles leave the denominator.** Ignoring half the image does not halve the
reported percentage — the question is what fraction of *what was looked at* changed.

**Alpha counts.** A pixel that went transparent looks unchanged over white and is a real
change.

**Regions are deliberately coarse.** They come from a 16 px block grid, merged until
nothing more joins — so a changed line of text is one region, not eleven. A box says
"look here"; one exact to the pixel is no better at that and costs far more to find.

## Overlays

```swift
try Overlay.write(comparing: a, with: b, to: url, style: .tint)
```

- `.tint` — the second image faded towards white, changed pixels in full-strength red.
  Full strength, not a blend: a change tinted 50% over a red button is invisible, which
  defeats the only purpose the picture has.
- `.mask` — changed pixels white on black.
- `.sideBySide` — the two images together, changes tinted in the second.

## Tested

17 tests on synthetic images with a known number of changed pixels in known places:
exact counts, region containment, adjacent blocks merging into one region, tolerance
suppression, alpha, the size refusal, and ignored rectangles both counted out of the
denominator and clipped at the edges. The region merge had an off-by-one that split two
changes separated by exactly one block — the most common spacing there is — and a test
found it.

## Used by

`shot compare`, in [`swift-shot-cli`](https://github.com/arraypress/swift-shot-cli).

## Licence

MIT.
