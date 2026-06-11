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
///
/// The whole sheet scrolls, so it stays legible at the `.medium` detent and at
/// the largest Dynamic Type sizes instead of clipping or cramming itself into
/// the available height.
struct PaywallView: View {
  @Environment(SubscriptionStore.self) private var subscriptions
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(spacing: Spacing.xl) {
        header
        featureList
        plans
        footer
      }
      .padding(.horizontal, Spacing.xl)
      .padding(.top, Spacing.xxl)
      .padding(.bottom, Spacing.xl)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.hidden)
    // Close as soon as the entitlement lands (purchase or restore), so a
    // successful upgrade doesn't leave the paywall sitting over the app.
    .onChange(of: subscriptions.isPlus) { _, isPlus in
      if isPlus { dismiss() }
    }
  }

  // MARK: Header

  /// The hero: a brand badge over the title and one-line pitch. The Plus glyph
  /// sits inside an accent-gradient squircle (the app-icon idiom, the same
  /// gradient disc the profile avatar uses) rather than floating bare on the
  /// sheet, so it reads as a deliberate emblem instead of a stray symbol.
  private var header: some View {
    VStack(spacing: Spacing.m) {
      heroBadge
      Text("Furioke Plus")
        .font(Typography.pageTitle)
        .multilineTextAlignment(.center)
      Text("The whole app is free. Plus lifts the limits when you want more.")
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }

  private var heroBadge: some View {
    RoundedRectangle(cornerRadius: Radii.xl, style: .continuous)
      .fill(Color.accentColor.gradient)
      .frame(width: 72, height: 72)
      .overlay {
        Image(systemName: "party.popper.fill")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(.white)
      }
      .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
      .accessibilityHidden(true)
  }

  // MARK: Features

  /// The three lifted limits, grouped into one inset card so the list reads as a
  /// single "what you get" unit. Each row gets a tinted icon tile (the Settings
  /// row idiom) instead of a repeated checkmark, giving the page some colour and
  /// rhythm without turning the opaque purchase surface into chrome.
  private var featureList: some View {
    VStack(alignment: .leading, spacing: Spacing.l) {
      featureRow(icon: "sparkles", "Unlimited AI translations")
      featureRow(icon: "character.book.closed.fill", "Unlimited word lookups")
      featureRow(icon: "rectangle.stack.fill", "Unlimited saved flashcards")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.l)
    .background(
      RoundedRectangle(cornerRadius: Radii.xl, style: .continuous)
        .fill(Color(.secondarySystemBackground))
    )
  }

  private func featureRow(icon: String, _ text: LocalizedStringKey) -> some View {
    HStack(spacing: Spacing.m) {
      RoundedRectangle(cornerRadius: Radii.md, style: .continuous)
        .fill(Color.accentColor.opacity(0.16))
        .frame(width: 32, height: 32)
        .overlay {
          Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
      Text(text)
        .font(Typography.body)
        .fixedSize(horizontal: false, vertical: true)
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
        .frame(height: 120)
    } else {
      VStack(spacing: Spacing.m) {
        ForEach(subscriptions.products, id: \.id) { product in
          planButton(product)
        }
      }
    }
  }

  /// One plan as a full-width button. The yearly plan is the prominent CTA with
  /// a "Save 37%" badge; monthly is the quieter glass alternative. The two
  /// branches differ only in button style — the label tree is shared — so the
  /// style is applied here and `planButtonBody` stays identical across both.
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

  /// The shared plan button. A spinner replaces the contents while this plan's
  /// own purchase is in flight, and every plan button is disabled while any
  /// purchase is running.
  private func planButtonBody(_ product: Product, isYearly: Bool) -> some View {
    let inFlight = subscriptions.purchaseInFlight == product.id
    let busy = subscriptions.purchaseInFlight != nil

    return Button {
      Task { await subscriptions.purchase(product) }
    } label: {
      planLabel(product, isYearly: isYearly, inFlight: inFlight, prominent: isYearly)
    }
    .controlSize(.large)
    .disabled(busy)
    .accessibilityLabel(accessibilityLabel(product, isYearly: isYearly))
  }

  /// The contents of a plan button: the plan name and its price on the leading
  /// edge, a "Save 37%" badge for the yearly plan on the trailing edge. While
  /// the purchase is in flight a spinner takes the whole row so the price and
  /// badge don't flicker mid-tap.
  private func planLabel(
    _ product: Product,
    isYearly: Bool,
    inFlight: Bool,
    prominent: Bool
  ) -> some View {
    HStack(spacing: Spacing.s) {
      if inFlight {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity)
      } else {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Text(planName(isYearly: isYearly))
            .font(.system(size: 17, weight: .semibold))
          Text(priceLine(product))
            .font(Typography.metadata)
            .foregroundStyle(prominent ? .primary : .secondary)
            .opacity(prominent ? 0.9 : 1)
        }
        Spacer(minLength: Spacing.s)
        if isYearly {
          Text("Save 37%")
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(.thinMaterial, in: Capsule())
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: 36)
    .padding(.vertical, Spacing.xs)
  }

  private func planName(isYearly: Bool) -> LocalizedStringKey {
    isYearly ? "Yearly" : "Monthly"
  }

  /// The plan's price line: "$29.99 / year" or "$3.99 / month". The price comes
  /// from StoreKit (`displayPrice`, localized to the storefront); the period word
  /// is localized here so non-English storefronts read "/ 年", "/ 月", etc.
  /// rather than the English unit glued onto a translated price.
  private func priceLine(_ product: Product) -> String {
    guard let unit = product.subscription?.subscriptionPeriod.unit else {
      return product.displayPrice
    }
    let price = product.displayPrice
    switch unit {
    case .year:
      return String(
        localized: "\(price) / year",
        comment: "Subscription price line, e.g. \"$29.99 / year\"."
      )
    case .month:
      return String(
        localized: "\(price) / month",
        comment: "Subscription price line, e.g. \"$3.99 / month\"."
      )
    case .week:
      return String(
        localized: "\(price) / week",
        comment: "Subscription price line, e.g. \"$0.99 / week\"."
      )
    case .day:
      return String(
        localized: "\(price) / day",
        comment: "Subscription price line, e.g. \"$0.99 / day\"."
      )
    @unknown default:
      return price
    }
  }

  /// The spoken label folds the plan name, price, and savings into one phrase so
  /// VoiceOver reads a single coherent button instead of stacked fragments.
  private func accessibilityLabel(_ product: Product, isYearly: Bool) -> String {
    let name = isYearly
      ? String(localized: "Yearly", comment: "A plan name, like \"Yearly\" or \"Monthly\".")
      : String(localized: "Monthly", comment: "A plan name, like \"Yearly\" or \"Monthly\".")
    let base = String(
      localized: "\(name), \(priceLine(product))",
      comment: "VoiceOver label for a plan button: plan name, then price line."
    )
    guard isYearly else { return base }
    return String(
      localized: "\(base), save 37 percent",
      comment: "VoiceOver label addition for the discounted yearly plan."
    )
  }

  // MARK: Footer

  /// Apple's standard auto-renewing-subscription EULA, the Terms of Service the
  /// App Store requires a subscription paywall to link. The privacy policy is the
  /// app's own, mirroring the web app's `/privacy` route.
  private static let termsURL = URL(
    string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
  )!
  private static let privacyURL = URL(string: "https://furioke.com/privacy")!

  private var footer: some View {
    VStack(spacing: Spacing.m) {
      Button("Restore Purchases") {
        Task { await subscriptions.restore() }
      }
      .font(Typography.metadata)
      .foregroundStyle(.secondary)
      .disabled(subscriptions.purchaseInFlight != nil)

      Text("Cancel anytime in Settings.")
        .font(Typography.furigana)
        .foregroundStyle(.tertiary)

      legalLinks
    }
    .frame(maxWidth: .infinity)
  }

  /// The required Terms of Service · Privacy Policy line. `Link`s (not buttons)
  /// so they read as outward navigation and hand the URL straight to the system,
  /// matching the app's other external links.
  private var legalLinks: some View {
    HStack(spacing: Spacing.s) {
      Link("Terms of Service", destination: Self.termsURL)
      Text("·")
        .foregroundStyle(.tertiary)
        .accessibilityHidden(true)
      Link("Privacy Policy", destination: Self.privacyURL)
    }
    .font(Typography.furigana)
    .foregroundStyle(.secondary)
  }
}
