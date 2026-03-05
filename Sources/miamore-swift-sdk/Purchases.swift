import Foundation

#if canImport(StoreKit)
import StoreKit

public enum MiaMorePurchaseOutcome: Sendable {
  case success(transactionId: String, originalTransactionId: String, productId: String)
  case pending
  case userCancelled
}

public enum MiaMorePurchaseError: Error {
  case productNotFound
  case failedVerification
}

extension MiaMoreSDK {
  /// Purchase using StoreKit 2.
  /// - Returns: a simplified outcome (success / pending / cancelled)
  public static func purchase(productId: String) async throws -> MiaMorePurchaseOutcome {
    let products = try await Product.products(for: [productId])
    guard let product = products.first else { throw MiaMorePurchaseError.productNotFound }

    let result = try await product.purchase()
    switch result {
    case .success(let verification):
      let transaction = try checkVerified(verification)
      await transaction.finish()

      // Optional: auto-link (best-effort)
      do {
        try await link(originalTransactionId: String(transaction.originalID))
      } catch {
        // swallow: app can call link manually
      }

      return .success(
        transactionId: String(transaction.id),
        originalTransactionId: String(transaction.originalID),
        productId: transaction.productID
      )

    case .pending:
      return .pending

    case .userCancelled:
      return .userCancelled

    @unknown default:
      return .pending
    }
  }

  /// Restore purchases (StoreKit 2).
  /// This triggers App Store sync and returns the set of active entitlements.
  public static func restore() async throws -> [MiaMorePurchaseOutcome] {
    try await AppStore.sync()

    var out: [MiaMorePurchaseOutcome] = []
    for await entitlement in Transaction.currentEntitlements {
      if case .verified(let t) = entitlement {
        out.append(.success(
          transactionId: String(t.id),
          originalTransactionId: String(t.originalID),
          productId: t.productID
        ))

        // best-effort link
        do { try await link(originalTransactionId: String(t.originalID)) } catch { }
      }
    }

    return out
  }

  private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
      throw MiaMorePurchaseError.failedVerification
    case .verified(let safe):
      return safe
    }
  }
}
#endif
