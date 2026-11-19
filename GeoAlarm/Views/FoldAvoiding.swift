// Copyright © 2026 Robert Bartis. All rights reserved.

// FoldAvoiding.swift
// Phase 3 (iOS 27 / iPhone Duo): keeps centered content (cards, onboarding)
// from straddling the fold while iPhone Duo is PARTIALLY folded ("book"
// posture). iOS 27.1 reports the fold as a reserved region of kind
// `.division`; by default `reservedRegions(kind:)` only returns ACTIVE
// regions, and the fold is only active while partially folded — fully open
// it's just a crease, so content stays centered exactly as before.
//
// When an active vertical fold is present, the content is laid out in the
// space on one side of it instead of across it. The Duo's fold sits in the
// middle of the inner display, so both sides are about equal width.
//
// On iOS earlier than 27.1, or any device without a fold, this is a no-op
// apart from filling the available space (callers use it full-screen).
// Note: reserved regions arrive after the first layout pass, so the inset is
// tracked with onGeometryChange rather than read once.

import SwiftUI

struct FoldAvoiding<Content: View>: View {
    private let content: Content
    /// Width to keep clear on the trailing side so content sits before the fold.
    @State private var trailingInset: CGFloat = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, trailingInset)
            .background {
                Color.clear
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        Self.inset(avoidingFoldIn: proxy)
                    } action: { newInset in
                        trailingInset = newInset
                    }
            }
    }

    /// Trailing inset that keeps content entirely before an active vertical fold.
    private static func inset(avoidingFoldIn proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return 0 }
        let gap: CGFloat = 8   // breathing room between content and the fold
        guard let fold = proxy.reservedRegions(kind: .division)
            .first(where: { $0.frame.height > $0.frame.width })   // vertical fold
        else { return 0 }
        return max(0, proxy.size.width - fold.frame.minX + gap)
    }
}
