import Observation
import StoreKit
import SwiftUI

/// Owns the Furioke Plus storefront on iOS: StoreKit 2 product loading,
/// purchase, restore, and the live transaction listener — plus the single
/// source of the client-side `isPlus` entitlement the UI gates on.
///
/// Entitlement model (mirrors the web's advisory client flag): `isPlus` is
/// derived locally from `Transaction.currentEntitlements`, which StoreKit
/// verifies cryptographically on-device, so gating is instant and works
/// offline. It is advisory — the backend re-derives the same entitlement from
/// the shared `subscriptions` table for real enforcement at `/api/translate`
/// and the flashcard cap. Every verified transaction is reported to the backend
/// (`PlusRegistrationService`) so that table stays in sync; App Store Server
/// Notifications keep it fresh for renewals and refunds with no app open.
///
/// A purchase binds to the signed-in Supabase user via `appAccountToken`, so
/// the backend can resolve the account from the signed transaction (the webhook
/// has no bearer token). Plus is reserved for a permanent account — a guest is
/// routed to sign-in first, the same gate translation and the library use.
@Observable
@MainActor
final class SubscriptionStore {
  /// The loaded Plus products, monthly first then yearly. Empty until
  /// `loadProducts()` resolves (offline, or before StoreKit responds).
  private(set) var products: [Product] = []

  /// Whether the signed-in user currently holds Plus, derived from the
  /// on-device entitlements. Drives every UI affordance; never the server gate.
  private(set) var isPlus = false

  /// The product id whose purchase or restore is in flight, so the paywall can
  /// show a spinner on the right button and disable the rest. Nil when idle.
  private(set) var purchaseInFlight: Product.ID?

  /// Drives the shared Plus paywall sheet. Settings, the out-of-quota notice's
  /// upgrade affordance, and the flashcard cap flip this; the app shell binds a
  /// sheet to it (hosted twice, like the sign-in prompt, so it can present from
  /// under the Now Playing cover too).
  var isPaywallPresented = false

  private let auth: AuthService
  private let registration: PlusRegistrationService

  /// The `Transaction.updates` listener, owned for the app's lifetime so
  /// renewals, Ask-to-Buy approvals, and cross-device purchases land while the
  /// app is open. Cancelled on deinit.
  @ObservationIgnored private var updatesTask: Task<Void, Never>?

  init(auth: AuthService) {
    self.auth = auth
    registration = PlusRegistrationService(auth: auth)
  }

  deinit {
    updatesTask?.cancel()
  }

  /// Begin observing transactions, load products, and refresh the entitlement.
  /// Idempotent: a second call only re-loads products. Called once from the
  /// composition root.
  func start() {
    if updatesTask == nil {
      updatesTask = Task { [weak self] in
        for await update in Transaction.updates {
          guard !Task.isCancelled else { break }
          await self?.handle(update)
        }
      }
    }
    Task { await loadProducts() }
    Task { await refreshEntitlement() }
  }

  /// Load the Plus products from the App Store, sorted into display order. A
  /// failure (offline, misconfigured ids) leaves `products` as-is so the paywall
  /// shows its loading state rather than an empty list.
  func loadProducts() async {
    guard let loaded = try? await Product.products(for: PlusProduct.all) else {
      return
    }
    products = loaded.sorted { lhs, rhs in
      let order = PlusProduct.all
      return (order.firstIndex(of: lhs.id) ?? 0) < (order.firstIndex(of: rhs.id) ?? 0)
    }
  }

  /// Buy `product`, binding the transaction to the signed-in user via
  /// `appAccountToken`. Plus is reserved for a permanent account, so a guest is
  /// routed to the sign-in prompt and the purchase is skipped. Returns once the
  /// purchase resolves; a user cancellation or pending (Ask-to-Buy) result is a
  /// quiet no-op.
  func purchase(_ product: Product) async {
    guard auth.requirePermanentAccount(), let userID = auth.sessionUserID else {
      return
    }
    purchaseInFlight = product.id
    defer { purchaseInFlight = nil }

    guard
      let result = try? await product.purchase(options: [
        .appAccountToken(userID),
      ])
    else {
      return
    }

    if case let .success(verification) = result {
      await fulfill(verification)
      isPaywallPresented = false
    }
  }

  /// Restore purchases on a new device or after a reinstall. `AppStore.sync()`
  /// re-pulls the user's transactions; the entitlement refresh then reflects any
  /// active Plus subscription.
  func restore() async {
    purchaseInFlight = nil
    try? await AppStore.sync()
    await refreshEntitlement()
  }

  // MARK: Transactions

  /// Apply a transaction delivered by the live `Transaction.updates` stream:
  /// finish it, refresh the entitlement, and report it to the backend.
  private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
    await fulfill(result)
  }

  /// Finish a verified transaction (so StoreKit stops re-delivering it), report
  /// it to the backend, and recompute `isPlus`. Unverified results are ignored —
  /// only App Store-signed transactions grant access.
  private func fulfill(_ result: VerificationResult<StoreKit.Transaction>) async {
    guard case let .verified(transaction) = result else { return }
    await registration.register(jws: result.jwsRepresentation)
    await transaction.finish()
    await refreshEntitlement()
  }

  /// Recompute `isPlus` from the on-device current entitlements: true when any
  /// verified, unrevoked Plus subscription's paid period has not ended.
  private func refreshEntitlement() async {
    var entitled = false
    for await result in Transaction.currentEntitlements {
      guard case let .verified(transaction) = result else { continue }
      guard PlusProduct.isPlus(transaction.productID) else { continue }
      let unexpired = (transaction.expirationDate ?? .distantFuture) > Date()
      if transaction.revocationDate == nil, unexpired {
        entitled = true
      }
    }
    isPlus = entitled
  }
}
