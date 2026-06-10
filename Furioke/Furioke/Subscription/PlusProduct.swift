import Foundation

/// The Furioke Plus product identifiers, registered as auto-renewable
/// subscriptions in App Store Connect (one subscription group, two durations).
/// They must match the identifiers in `Furioke.storekit` and the products
/// configured in App Store Connect exactly.
enum PlusProduct {
  static let monthly = "com.magicparklabs.Furioke.plus.monthly"
  static let yearly = "com.magicparklabs.Furioke.plus.yearly"

  /// Every Plus product id, in display order (monthly first, yearly second).
  /// Used to load products and to recognise a Plus entitlement among the user's
  /// transactions.
  static let all: [String] = [monthly, yearly]

  static func isPlus(_ productID: String) -> Bool {
    all.contains(productID)
  }
}
