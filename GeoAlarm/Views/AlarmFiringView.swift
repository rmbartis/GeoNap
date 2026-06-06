// AlarmFiringView.swift
// Full-screen alarm screen shown when a geo-alarm fires.
// Displayed as a .fullScreenCover from ContentView while AlarmManager.firingAlarm is set.
//
// Interaction:
//   • Slide-to-dismiss  → stops looping sound, clears firingAlarm
//   • Snooze 10 min     → stops sound, snoozes alarm

import SwiftUI

struct AlarmFiringView: View {
    let alarm: NapAlarm
    var onDismiss: () -> Void
    var onSnooze:  () -> Void

    @Environment(\.languageBundle) private var bundle
    @State private var pulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                Spacer()

                // ── Pulsing location icon ─────────────────────────────────
                ZStack {
                    // Three concentric rings that breathe with the icon
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .stroke(
                                Color.red.opacity(0.25 - Double(i) * 0.07),
                                lineWidth: 1.5
                            )
                            .frame(width: 80 + CGFloat(i) * 44,
                                   height: 80 + CGFloat(i) * 44)
                            .scaleEffect(pulse)
                            .animation(
                                .easeInOut(duration: 1.1)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.18),
                                value: pulse
                            )
                    }

                    Image(systemName: "location.fill")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundColor(.red)
                        .scaleEffect(pulse)
                        .animation(
                            .easeInOut(duration: 1.1)
                                .repeatForever(autoreverses: true),
                            value: pulse
                        )
                }
                .frame(height: 220)

                // ── Trigger label ─────────────────────────────────────────
                Text(NSLocalizedString(alarm.regionEvent.rawValue, bundle: bundle, comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.bottom, 12)

                // ── Alarm name ────────────────────────────────────────────
                Text(alarm.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // ── Optional note ─────────────────────────────────────────
                if !alarm.note.isEmpty {
                    Text(alarm.note)
                        .font(.system(size: 17))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                }

                Spacer()

                // ── Snooze button ─────────────────────────────────────────
                Button(action: onSnooze) {
                    Text(NSLocalizedString("Snooze 10 min", bundle: bundle, comment: ""))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 220, height: 52)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .padding(.bottom, 28)

                // ── Slide-to-dismiss slider ───────────────────────────────
                DismissSlider(bundle: bundle, onDismiss: onDismiss)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 52)
            }
        }
        .onAppear { pulse = 1.12 }
    }
}

// MARK: - Slide-to-dismiss

private struct DismissSlider: View {
    let bundle: Bundle
    var onDismiss: () -> Void

    @State private var offset: CGFloat = 0

    private let height: CGFloat    = 62
    private let thumbDiameter: CGFloat = 54
    private let padding: CGFloat   = 4

    var body: some View {
        GeometryReader { geo in
            let maxOffset = geo.size.width - thumbDiameter - padding * 2
            let progress  = maxOffset > 0 ? (offset / maxOffset) : 0

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(Color.white.opacity(0.13))
                    .frame(height: height)

                // Fill strip that grows with the thumb
                Capsule()
                    .fill(Color.red.opacity(0.25 * progress))
                    .frame(width: max(0, offset + thumbDiameter / 2 + padding),
                           height: height)

                // Hint label — fades out as thumb advances
                Text(NSLocalizedString("Slide to dismiss", bundle: bundle, comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(max(0, 0.55 * (1 - progress * 1.8))))
                    .frame(maxWidth: .infinity)
                    .padding(.leading, thumbDiameter + padding * 3)

                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay(
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.red)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 2)
                    .offset(x: offset + padding)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { v in
                                offset = max(0, min(v.translation.width, maxOffset))
                            }
                            .onEnded { _ in
                                if offset >= maxOffset * 0.82 {
                                    withAnimation(.spring(response: 0.2)) {
                                        offset = maxOffset
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                        onDismiss()
                                    }
                                } else {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                        offset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: height)
        }
        .frame(height: height)
    }
}

#Preview {
    AlarmFiringView(
        alarm: NapAlarm(
            name: "Central Station",
            latitude: 40.712,
            longitude: -74.006,
            radius: 200,
            regionEvent: .onEntry,
            note: "Change to the blue line"
        ),
        onDismiss: {},
        onSnooze:  {}
    )
    .environmentObject(LanguageManager.shared)
    .environment(\.languageBundle, Bundle.main)
}
