# SPFKVideo

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-video)](https://github.com/ryanfrancesconi/spfk-video/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Reads, plays, samples and trims video files through AVFoundation, with no UI. Video is first-class
in both an audio library and an image library, so this package carries no audio or image dependency
and either kind of app can reach it.

It reads a file's video track and capture metadata, extracts frames and caches them on disk,
controls playback without drawing anything, lists a file's audio tracks for the user to choose
between, and trims losslessly by remuxing rather than re-encoding.

The views belong to spfk-video-ui. Containers AVFoundation cannot open, such as Matroska, belong to
spfk-matroska, which extends the types here with entry points that accept any container; a caller
that branches on the container itself has missed them.

## Constraints

- MXF and the professional codecs are readable only after `ProVideoFormats.register()`, called
  before the first asset is opened, and only where Apple's Pro Video Formats package is installed.
- Cached frames are keyed by file and time with no freshness check. After rewriting a video in
  place, delete its cached frames, or the old timeline keeps being served.
- A lossless trim lands exactly on its in-point without snapping to a keyframe, so an editor must not
  snap trim handles to keyframes.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
