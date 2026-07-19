# SPFKVideo

[![CI](https://img.shields.io/github/actions/workflow/status/ryanfrancesconi/spfk-video/ci.yml?branch=development)](https://github.com/ryanfrancesconi/spfk-video/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-video)](https://github.com/ryanfrancesconi/spfk-video/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Video utilities for Swift, built on Apple's [AVFoundation](https://developer.apple.com/documentation/avfoundation) framework.

**Status: early scaffold.** No implemented functionality yet — see the implementation plan for the current design.

## Planned: Frame Extraction

Fills a real gap in Apple's own frameworks — [Vision](https://developer.apple.com/documentation/vision) has no video-native classification or sampling API, only single-image requests. `VideoFrameExtractor` will provide a UI-agnostic, async/await-native primitive for extracting still frames from a video asset at given timestamps, with configurable output size and tolerance — built on `AVAssetImageGenerator`.

Named neutrally (`spfk-video`, not `spfk-video-frame-extraction`) to comfortably hold other well-justified, similarly-scoped video utilities later without a package rename — not a signal of broader scope today.

## Dependencies

| Package | Description |
|---------|-------------|
| [spfk-base](https://github.com/ryanfrancesconi/spfk-base) | Core utilities and extensions |
| [spfk-testing](https://github.com/ryanfrancesconi/spfk-testing) | Test infrastructure (test target only) |

## Requirements

- **Swift** 6.2+
- **macOS** 13+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
