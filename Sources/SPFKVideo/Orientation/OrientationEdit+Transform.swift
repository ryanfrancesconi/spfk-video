// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-video

import CoreGraphics
import Foundation
import SPFKBase

extension OrientationEdit {
    /// This edit as a transform in display coordinates (y down, origin top left), for a picture
    /// displayed at `size` before the edit. The result maps that picture onto `[0, w′] × [0, h′]`.
    ///
    /// A track displaying with matrix `T` displays this edit with `T.concatenating(transform(displaying:))`.
    public func transform(displaying size: CGSize) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        var width = size.width
        var height = size.height

        if isMirrored {
            result = result.concatenating(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0))
        }

        for _ in 0 ..< quarterTurns {
            result = result.concatenating(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0))
            swap(&width, &height)
        }

        return result
    }

    /// The orientation a track matrix displays, ignoring its translation. `nil` for a matrix that
    /// also scales or skews.
    public init?(trackTransform transform: CGAffineTransform) {
        let tolerance = 1e-6
        let linear = [transform.a, transform.b, transform.c, transform.d]

        let match = Self.allCases.first { edit in
            let candidate = edit.transform(displaying: CGSize(width: 1, height: 1))
            return zip([candidate.a, candidate.b, candidate.c, candidate.d], linear).allSatisfy { abs($0 - $1) < tolerance }
        }

        guard let match else { return nil }

        self = match
    }
}

extension CGAffineTransform {
    /// `self` followed by `edit`, for a track whose natural size is `naturalSize`. The displayed
    /// rectangle is moved to the origin first, so a track matrix with a stray translation still
    /// lands on `[0, w′] × [0, h′]`.
    public func applying(_ edit: OrientationEdit, naturalSize: CGSize) -> CGAffineTransform {
        let displayed = CGRect(origin: .zero, size: naturalSize).applying(self)

        return concatenating(CGAffineTransform(translationX: -displayed.minX, y: -displayed.minY))
            .concatenating(edit.transform(displaying: displayed.size))
    }
}
