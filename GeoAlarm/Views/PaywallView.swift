// Copyright © 2026 Robert Bartis. All rights reserved.

// PaywallView.swift
// Phase 3, item 10: the screen where a user compares Free/Silver/Gold/
// Platinum and taps to buy. The only place in the app that calls
// PurchaseManager.purchase(_:) / .restorePurchases() — everything upstream
// of this view (TierGatedModifier's lock badge, the Settings "See Plans"
// row) just presents it as a sheet; this view owns the actual buy/restore
// flow and its loading/error states.
//
// Apple requirements this satisfies: a Restore Purchases button, and links
// to Terms of Use and a Privacy Policy (App Store Review Guideline 3.1.2).
// The Privacy Policy link opens PrivacyView() in-app (already built). The
// Terms of Use link opens Apple's own Standard EULA
// (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) as an
// interim stand-in — Apple explicitly permits using their standard EULA for
// apps that haven't written a custom one; swap this for a custom Terms of
// Use page once Phase 4 item 14 exists.
//
// Localization: English only for now (see the "Paywall" section in
// en.lproj/Localizable.strings) — the other 12 languages are Phase 4 item
// 18's separate, later scope, not part of item 10.

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.languageBundle) private var bundle
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var purchaseManager = PurchaseManager.shared

    @State private var purchasingProductID: String?
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if purchaseManager.products.isEmpty && purchaseManager.isLoadingProducts {
                        ProgressView(NSLocalizedString("paywall.loadingProducts", bundle: bundle, comment: ""))
                            .padding(.top, 40)
                    } else {
                        freeTierCard

                        tierCard(
                            tier: .silver,
                            productID: ProductID.silverAnnual,
                            color: .gray,
                            icon: "medal.fill",
                            captionKey: "paywall.silver.caption",
                            featureKeys: ["paywall.silver.feature1", "paywall.silver.feature2", "paywall.silver.feature3", "paywall.silver.feature4"],
                            periodKey: "paywall.period.year"
                        )

                        tierCard(
                            tier: .gold,
                            productID: ProductID.goldAnnual,
                            color: .yellow,
                            icon: "medal.fill",
                            captionKey: "paywall.gold.caption",
                            featureKeys: ["paywall.gold.feature1", "paywall.gold.feature2", "paywall.gold.feature3", "paywall.gold.feature4", "paywall.gold.feature5", "paywall.gold.feature6"],
                            periodKey: "paywall.period.year"
                        )

                        tierCard(
                            tier: .platinum,
                            productID: ProductID.platinum,
                            color: .purple,
                            icon: "crown.fill",
                            captionKey: "paywall.platinum.caption",
                            featureKeys: ["paywall.platinum.feature1", "paywall.platinum.feature2", "paywall.platinum.feature3", "paywall.platinum.feature4", "paywall.platinum.feature5", "paywall.platinum.feature6"],
                            periodKey: "paywall.period.oneTime"
                        )
                    }

                    restoreButton

                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("paywall.notNow", bundle: bundle)
                    }
                }
            }
            .alert(Text("paywall.error.title", bundle: bundle), isPresented: $showErrorAlert) {
                Button {} label: { Text("OK", bundle: bundle) }
            } message: {
                Text(errorMessage)
            }
            .task {
                // Cheap no-op if start() already ran at app launch — loadProducts()
                // just re-fetches, which is fine if the sheet is opened before
                // that first launch-time fetch has completed.
                if purchaseManager.products.isEmpty {
                    await purchaseManager.loadProducts()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .padding(.top, 12)
            Text("paywall.title", bundle: bundle)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("paywall.subtitle", bundle: bundle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(String(format: NSLocalizedString("paywall.currentPlan", bundle: bundle, comment: ""), EntitlementManager.currentTier.description))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Free tier (informational, not purchasable)

    private var freeTierCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("paywall.freeTier.title", bundle: bundle)
                    .font(.subheadline.bold())
                Text("paywall.freeTier.caption", bundle: bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Purchasable tier card

    @ViewBuilder
    private func tierCard(
        tier: AppTier,
        productID: String,
        color: Color,
        icon: String,
        captionKey: String,
        featureKeys: [String],
        periodKey: String
    ) -> some View {
        let product = purchaseManager.products.first { $0.id == productID }
        let owned = EntitlementManager.isEntitled(to: tier)
        let isPurchasing = purchasingProductID == productID

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tier.description, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(color)
                Spacer()
                if let product {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(product.displayPrice)
                            .font(.subheadline.bold())
                        Text(LocalizedStringKey(periodKey), bundle: bundle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(LocalizedStringKey(captionKey), bundle: bundle)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(featureKeys, id: \.self) { key in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.caption2.bold())
                            .foregroundStyle(color)
                            .padding(.top, 2)
                        Text(LocalizedStringKey(key), bundle: bundle)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            actionButton(tier: tier, product: product, owned: owned, isPurchasing: isPurchasing, color: color)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(owned ? color : Color.clear, lineWidth: 2)
        )
    }

    @ViewBuilder
    private func actionButton(tier: AppTier, product: Product?, owned: Bool, isPurchasing: Bool, color: Color) -> some View {
        if owned {
            Label {
                Text("paywall.action.included", bundle: bundle)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.subheadline.bold())
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if let product {
            Button {
                buy(product)
            } label: {
                if isPurchasing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(tier == .platinum ? "paywall.action.buy" : "paywall.action.subscribe", bundle: bundle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(color)
            .disabled(isPurchasing || purchasingProductID != nil)
            .accessibilityIdentifier("paywallBuyButton.\(tier.description.lowercased())")
        } else {
            // Product metadata hasn't loaded (e.g. offline, or ASC not yet
            // reachable) — show a disabled placeholder rather than nothing,
            // so the layout doesn't jump once it does load.
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            restore()
        } label: {
            Text("paywall.action.restorePurchases", bundle: bundle)
                .font(.subheadline)
        }
        .padding(.top, 8)
        .accessibilityIdentifier("paywallRestoreButton")
    }

    // MARK: - Legal footer

    private var legalFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                NavigationLink {
                    PrivacyView()
                } label: {
                    Text("paywall.legal.privacyPolicy", bundle: bundle)
                        .font(.caption)
                }
                // Interim: Apple's Standard EULA, until Phase 4 item 14
                // (a custom Terms of Use) exists — see file header.
                Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                    Text("paywall.legal.termsOfUse", bundle: bundle)
                        .font(.caption)
                }
            }
            Text("paywall.legal.disclosure", bundle: bundle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func buy(_ product: Product) {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        Task {
            defer { purchasingProductID = nil }
            do {
                try await purchaseManager.purchase(product)
            } catch PurchaseError.userCancelled {
                // Silent — no error banner for a plain cancel.
            } catch PurchaseError.pending {
                errorMessage = NSLocalizedString("paywall.pending", bundle: bundle, comment: "")
                showErrorAlert = true
            } catch {
                CrashReporter.record(error, context: "PaywallView.buy failed for \(product.id)")
                errorMessage = NSLocalizedString("paywall.error.generic", bundle: bundle, comment: "")
                showErrorAlert = true
            }
        }
    }

    private func restore() {
        Task {
            do {
                try await purchaseManager.restorePurchases()
            } catch {
                CrashReporter.record(error, context: "PaywallView.restore failed")
                errorMessage = NSLocalizedString("paywall.error.generic", bundle: bundle, comment: "")
                showErrorAlert = true
            }
        }
    }
}

#Preview {
    PaywallView()
}
