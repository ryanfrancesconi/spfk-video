# SPFKVideo

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-video)](https://github.com/ryanfrancesconi/spfk-video/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-video%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-video)

Video reading, frame extraction, playback control and lossless trimming for Swift, built on Apple's
[AVFoundation](https://developer.apple.com/documentation/avfoundation) framework. Everything here is
UI-agnostic and async/await-native — no AppKit, so both products and the shared video views can
reach it. The views themselves are in
[spfk-video-ui](https://github.com/ryanfrancesconi/spfk-video-ui).

## Reading a video

`VideoTrackReader.read(from:)` returns a video track and QuickTime user data together. It reads
video-technical properties (resolution, frame rate, codec, pixel aspect ratio, rotation) via `AVAssetTrack`, and QuickTime user-data (GPS, capture device, creation date) via `AVMetadataItem`. Both reads are best-effort and independent — a failure in one doesn't suppress the other. QuickTime metadata is merged from both the modern `mdta` keyspace (`.quickTimeMetadata`) and the legacy `udta` keyspace (`.quickTimeUserData`), since which keyspace a given file populates varies by capture device/software.

## Frame extraction

**For a container that may not be AVFoundation-openable, call `VideoFrameExtractor.framesForAnyContainer` instead** — it lives in [spfk-matroska](https://github.com/ryanfrancesconi/spfk-matroska), which extends this type, and routes to the demuxer for `.mkv`/`.webm`/`.mka` while leaving everything else on the path below. A caller writing its own `if isMatroska` branch has missed it.

Frame extraction uses `AVAssetImageGenerator`'s `images(for:)` async sequence. Wide tolerance (0.3s default) lets the generator reuse the nearest already-decoded frame rather than forcing exact decoding — significantly faster for thumbnail and classification sampling that doesn't need frame-perfect accuracy. A timestamp whose frame fails to extract is simply absent from the result rather than failing the whole batch.

## Frame caching

`VideoFrameDataStore` is an actor providing a disk cache for extracted frames, keyed by source video and requested timestamp. Layout is one subdirectory per video (named `url.sha256`) holding one JPEG per frame, named by integer millisecond timestamp plus a tier suffix — `2000_thumb.jpg`, `2000_full.jpg`. Milliseconds are integers deliberately, since floating-point in a filename round-trips inconsistently.

Two tiers are available via `VideoFrameTier`: `.thumbnail` for UI display and `.fullQuality` for classification input. Frames are stored as JPEG at an explicit quality of 0.8 — many frames per file makes format and quality choice matter more here than for a one-entry-per-file cache.

`VideoFrameDataStoreAccess` is the protocol a host app's data layer conforms to in order to expose the store to its UI without handing over the store itself.

**Frames are keyed by URL and timestamp with no freshness check.** A file whose content changed at the same path — a trim rendered in place — will otherwise keep serving frames from the old timeline. Call `delete(url:)` after rewriting a video; `prune(activeURLs:)` handles whole-cache housekeeping and does not detect content changes.

## Playback

| Type | Description |
|------|-------------|
| **`VideoTransport`** | Load, play, pause, seek and speed for one video |
| **`PlaybackSpeed`** | The selectable speeds, as a fixed list for menus |
| **`AVPlayerSeekCoalescer`** | Collapses seeks arriving faster than `AVPlayer` can serve them |
| **`FrameSeekFilter`** | Drops a seek that cannot change the picture |

`VideoTransport` owns an `AVPlayer` and nothing visual, so the same transport drives an inline
preview or a detached window without knowing either exists. **It does not drive the playhead** — an
animation is seeded from the player's timebase so the render server carries the motion, and the
transport's job is to report when that seed went stale, not to interpolate position itself.

A drag emits one seek per mouse-move. Issued directly, each cancels the one still in flight and the
picture can starve — no seek survives long enough to deliver a frame. The coalescer performs the
first and the newest and drops what fell between, landing on the position last asked for. The filter
sits in front of it, identifying a target by the frame containing it so an exact duplicate costs no
decode; an allowed target passes through unquantized, so a seek that survives lands where it was
asked to.

## Editing

`VideoEditRenderer` applies a trim and writes the result out. It uses a passthrough export, so the
media is remuxed rather than re-encoded — every track is copied bit for bit and the export costs
milliseconds rather than minutes. The trim is still exact on both ends: the export keeps the partial
leading GOP and writes an edit list starting presentation at the requested time, so the first
presented frame is the frame at the in-point even when the preceding keyframe is over a second
earlier. **This is why an editor must not snap trim handles to keyframes** — there is no drift to
compensate for, and snapping would move the user's in-point for nothing.

The cost is that up to one extra GOP of leading video stays in the file. Anything honoring edit
lists — all of AVFoundation, and ffmpeg by default — sees the exact trim; a tool that ignores them
sees the lead-in. That is inherent to lossless trimming.

Metadata needs no special handling: a passthrough export preserves the iTunes and both QuickTime
keyspaces intact, capture date, device and GPS included, so there is deliberately no metadata-copy
pass here.

It takes a `TrimDescription` rather than an audio edit type on purpose — this package must stay free
of any audio dependency so TorchTag can reach it too.

## Audio tracks of a video

| Type | Description |
|------|-------------|
| **`AudioTrackDescription`** | One selectable audio track, in terms neither playback backend owns |
| **`AudioTrackReader`** | Lists them through AVFoundation |

A dual-audio film states two, and which one plays is the user's choice rather than the muxer's
ordering. The two backends answer that by unrelated mechanisms — the Matroska demuxer reopens on a
different track number, AVFoundation enables a track on a live player item — so nothing in
`AudioTrackDescription` mentions reopening, seeking or a track number. It lives here because both
backends and both products must reach it, and it cannot live in `spfk-matroska`, which already
depends on this package.

`AudioTrackReader` returns an empty array rather than throwing for a container AVFoundation cannot
open: that file has a different backend, and a listing that failed and one that found nothing lead
to the same place.

## Display

`VideoTechnicalProperties` is the presentation-ready model — resolution, frame rate, codec, pixel
aspect ratio, rotation, GPS, device make, model and software, and capture date — pre-formatted as
localized strings keyed by its `Key`, with the GPS coordinate additionally kept raw for consumers
that need more than to print it. It has no view-layer dependency; wiring these fields into AppKit is
done by a consumer's own extension.

`captureDate` is deliberately distinct from the filesystem's creation and modification dates: it is
the QuickTime user-data creation date, when the footage was actually recorded.

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
