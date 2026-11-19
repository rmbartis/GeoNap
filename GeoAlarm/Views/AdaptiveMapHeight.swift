// Copyright © 2026 Robert Bartis. All rights reserved.

// AdaptiveMapHeight.swift
// Phase 3 (iOS 27 / iPhone Duo): embedded maps were a fixed 220 pt tall, which
// left them a thin strip on the iPhone Duo's open inner display and on iPad.
// Use the compact height on phone-sized layouts and a taller one when BOTH
// size classes are regular (open Duo, iPad), so the radius circle is readable.

import SwiftUI

private struct AdaptiveMapHeight: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let compact: CGFloat
    let regular: CGFloat

    func body(content: Content) -> some View {
        let roomy = horizontalSizeClass == .regular && verticalSizeClass == .regular
        return content.frame(height: roomy ? regular : compact)
    }
}

extension View {
    /// Height for maps embedded in forms/lists: `compact` on phone-sized
    /// layouts, `regular` when there's room in both directions.
    func adaptiveMapHeight(compact: CGFloat = 220, regular: CGFloat = 380) -> some View {
        modifier(AdaptiveMapHeight(compact: compact, regular: regular))
    }
}
