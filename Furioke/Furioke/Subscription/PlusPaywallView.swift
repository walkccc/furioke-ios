import StoreKit
import SwiftUI

/// The Furioke Plus upgrade sheet. Opened from Settings, the out-of-quota
/// notice, and the flashcard cap. A content surface (legible, opaque) rather
/// than glass — it's a purchase decision, not chrome.
///
/// The whole app stays free; Plus lifts the limits for the people who hit them.
/// Each plan button starts a StoreKit purchase through `SubscriptionStore`,
/// which binds the transaction to the signed-in account and reports it to the
/// backend so the entitlement holds everywhere. The sheet closes itself once
/// `isPlus` flips true.
struct PlusPaywallView: View {
  @Environment(SubscriptionStore.self) private var subscriptions
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: Spacing.xl) {
      header
      featureList
      Spacer(minLength: 0)
      plans
      footer
    }
    .padding(.horizontal, Spacing.xl)
    .padding(.top, Spacing.xxl)
    .padding(.bottom, Spacing.xl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    // Close as soon as the entitlement lands (purchase or restore), so a
    // successful upgrade doesn't leave the paywall sitting over the app.
    .onChange(of: subscriptions.isPlus) { _, isPlus in
      if isPlus { dismiss() }
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(spacing: Spacing.s) {
      Image(systemName: "sparkles")
        .font(.system(size: 34, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      Text("Furioke Plus")
        .font(Typography.pageTitle)
      Text("The whole app is free. Plus lifts the limits when you want more.")
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
  }

  // MARK: Features

  private var featureList: some View {
    VStack(alignment: .leading, spacing: Spacing.m) {
      featureRow("Unlimited AI translations and word lookups")
      featureRow("Unlimited saved flashcards")
      featureRow("Support a calm, ad-free app")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func featureRow(_ text: LocalizedStringKey) -> some View {
    HStack(spacing: Spacing.s) {
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(Color.accentColor)
        .accessibilityHidden(true)
      Text(text)
        .font(Typography.body)
      Spacer(minLength: 0)
    }
  }

  // MARK: Plans

  @ViewBuilder
  private var plans: some View {
    if subscriptions.products.isEmpty {
      ProgressView()
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .frame(height: 96)
    } else {
      VStack(spacing: Spacing.m) {
        ForEach(subscriptions.products, id: \.id) { product in
          planButton(product)
        }
      }
    }
  }

  /// One plan as a full-width button: the yearly plan is the prominent CTA with
  /// a best-value caption; monthly is the quieter glass alternative. A spinner
  /// replaces the price while its own purchase is in flight.
  @ViewBuilder
  private func planButton(_ product: Product) -> some View {
    let isYearly = product.id == PlusProduct.yearly
    if isYearly {
      planButtonBody(product, isYearly: true)
        .buttonStyle(.glassProminent)
    } else {
      planButtonBody(product, isYearly: false)
        .buttonStyle(.glass)
    }
  }

  /// The shared button body for both plans; only the button style differs, so
  /// `planButton` applies that and this stays identical across the two.
  private func planButtonBody(_ product: Product, isYearly: Bool) -> some View {
    let inFlight = subscriptions.purchaseInFlight == product.id
    let busy = subscriptions.purchaseInFlight != nil

    return Button {
      Task { await subscriptions.purchase(product) }
    } label: {
      HStack(spacing: Spacing.s) {
        if inFlight {
          ProgressView().controlSize(.small)
        } else {
          Text(planLabel(product, isYearly: isYearly))
            .font(.system(size: 17, weight: .semibold))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.s)
    }
    .controlSize(.large)
    .disabled(busy)
    .accessibilityLabel(planLabel(product, isYearly: isYearly))
  }

  /// The plan's price line: "$29.99 / year · Save 37%" for yearly, "$3.99 /
  /// month" for monthly. The price comes from StoreKit (`displayPrice`,
  /// localized to the store front); the period comes from the subscription unit.
  private func planLabel(_ product: Product, isYearly: Bool) -> String {
    let period = product.subscription.map { periodLabel($0.subscriptionPeriod) } ?? ""
    let base = "\(product.displayPrice)\(period)"
    return isYearly ? "\(base) · Save 37%" : base
  }

  private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
    switch period.unit {
    case .year: " / year"
    case .month: " / month"
    case .week: " / week"
    case .day: " / day"
    @unknown default: ""
    }
  }

  // MARK: Footer

  private var footer: some View {
    VStack(spacing: Spacing.s) {
      Button("Restore Purchases") {
        Task { await subscriptions.restore() }
      }
      .font(Typography.metadata)
      .foregroundStyle(.secondary)
      .disabled(subscriptions.purchaseInFlight != nil)

      Text("Cancel anytime in Settings.")
        .font(Typography.furigana)
        .foregroundStyle(.tertiary)
    }
  }
}
