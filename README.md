# SPFKVideo

[![CI](https://github.com/ryanfrancesconi/spfk-video/actions/workflows/ci.yml/badge.svg?branch=development)](https://github.com/ryanfrancesconi/spfk-video/actions/workflows/ci.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Video frame extraction and caching for Swift, built on Apple's [AVFoundation](https://developer.apple.com/documentation/avfoundation) framework.

Fills a real gap in Apple's own frameworks — [Vision](https://developer.apple.com/documentation/vision) has no video-native classification or sampling API, only single-image requests. `VideoFrameExtractor` provides a UI-agnostic, async/await-native primitive for extracting still frames from a video asset at given timestamps, with configurable output size and tolerance.

Named neutrally (`spfk-video`, not `spfk-video-frame-extraction`) to comfortably hold other well-justified, similarly-scoped video utilities later without a package rename.

## Usage

### Frame Extraction

```swift
import SPFKVideo

// Extract frames at specific timestamps, keyed by the requested time.
let frames = try await VideoFrameExtractor.frames(
    from: videoURL,
    at: [1.0, 3.0, 5.0, 7.0],
    maximumSize: CGSize(width: 300, height: 0)  // width-constrained, height scales proportionally
)

let frameAt3s = frames[3.0]  // CGImage?

// Get the video track's own duration, independent of a sibling audio track's length.
let duration = try await VideoFrameExtractor.duration(of: videoURL)
```

`frames(from:at:maximumSize:tolerance:)` uses `AVAssetImageGenerator`'s `images(for:)` async sequence. Wide tolerance (0.3s default) lets the generator reuse the nearest already-decoded frame rather than forcing exact decoding — significantly faster for thumbnail and classification sampling that doesn't need frame-perfect accuracy. A timestamp whose frame fails to extract is simply absent from the result rather than failing the whole batch.

### Frame Caching

```swift
import SPFKVideo

let store = try VideoFrameDataStore(inDirectory: cacheDirectoryURL)

try await store.insert(.thumbnail, cgImage: frame, timestamp: 3.0, for: videoURL)
let cached = await store.fetch(.thumbnail, timestamp: 3.0, for: videoURL)  // CGImage?
let has = await store.exists(.thumbnail, timestamp: 3.0, for: videoURL)   // Bool

// Remove every cached video not present in the active set.
await store.prune(activeURLs: currentLibraryURLs)
```

`VideoFrameDataStore` is a disk cache for extracted frames, keyed by source video (`URL.sha256`) and timestamp, stored as JPEG under `Data/Video/<fileKey>/`. `VideoFrameTier` distinguishes `.thumbnail` (UI scrubber display) from `.fullQuality` (classification input, reserved for a future video-classification consumer sharing this same cache).

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Core utilities and extensions |
| [spfk-testing](https://github.com/ryanfrancesconi/spfk-testing) | Test infrastructure (test target only) |

## Requirements

- **Platforms:** macOS 13+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
