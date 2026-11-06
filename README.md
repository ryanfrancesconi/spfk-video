# SPFKVideo

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-video)](https://github.com/ryanfrancesconi/spfk-video/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Video file reading, playback control, frame extraction and trimming through AVFoundation, with no
UI and no audio or image library dependency.

## Features

- Read a file's video track properties and capture metadata, including QuickTime user data and MXF
- Extract frames and cache them on disk
- Playback control without drawing (`VideoTransport`)
- List a file's audio tracks
- Lossless trim by remuxing, exact to the in-point (`VideoEditRenderer`)
- Format conversion with AVFoundation export presets (`VideoFormatConverter`)
- MXF and professional codecs after `ProVideoFormats.register()`, where Apple's Pro Video Formats
  package is installed

## Notes

- Cached frames are keyed by file and time, with no freshness check. Delete a file's cached frames
  after rewriting it in place.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
