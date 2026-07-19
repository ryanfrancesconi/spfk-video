# SPFKVideo

[![CI](https://img.shields.io/github/actions/workflow/status/ryanfrancesconi/spfk-video/ci.yml?branch=development)](https://github.com/ryanfrancesconi/spfk-video/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-video)](https://github.com/ryanfrancesconi/spfk-video/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Video frame extraction and track/metadata reading for Swift, built on Apple's [AVFoundation](https://developer.apple.com/documentation/avfoundation) framework.

`VideoFrameExtractor` provides a UI-agnostic, async/await-native primitive for extracting still frames from a video asset at given timestamps, with configurable output size and tolerance. `VideoTrackReader` reads video-technical properties and QuickTime user-data metadata.

## Usage

### Video Track & QuickTime Metadata

```swift
import SPFKVideo

let result = await VideoTrackReader.read(from: videoURL)
let videoTrack = result.videoTrack                // VideoTrackProperties?
let quickTimeUserData = result.quickTimeUserData  // QuickTimeUserData?

print(videoTrack?.width, videoTrack?.height, videoTrack?.frameRate, videoTrack?.codec)
print(quickTimeUserData?.deviceMake, quickTimeUserData?.latitude, quickTimeUserData?.longitude)
```

`VideoTrackReader.read(from:)` reads video-technical properties (resolution, frame rate, codec, pixel aspect ratio, rotation) via `AVAssetTrack`, and QuickTime user-data (GPS, capture device, creation date) via `AVMetadataItem`. Both reads are best-effort and independent — a failure in one doesn't suppress the other. QuickTime metadata is merged from both the modern `mdta` keyspace (`.quickTimeMetadata`) and the legacy `udta` keyspace (`.quickTimeUserData`), since which keyspace a given file populates varies by capture device/software.

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

This package is extraction only — no persistence. Disk caching of extracted frames is an application-level concern and lives in the consuming app's own data layer.

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Core utilities and extensions |
| [spfk-testing](https://github.com/ryanfrancesconi/spfk-testing) | Test infrastructure (test target only) |

## Requirements

- **Platforms:** macOS 13+, iOS 16+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
