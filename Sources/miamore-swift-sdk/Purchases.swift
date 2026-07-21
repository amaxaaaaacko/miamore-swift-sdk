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
  /// The requested billing plan requires StoreKit commitment-plan symbols that aren't available in this build.
  /// Build the SDK with `MIAMORE_ENABLE_STOREKIT_COMMITMENT_PLANS` using Xcode 26.5 SDK or newer.
  case unsupportedBillingPlanType
}

extension MiaMoreSDK {
  /// Purchase using StoreKit 2.
  /// - Returns: a simplified outcome (success / pending / cancelled)
  public static func purchase(productId: String) async throws -> MiaMorePurchaseOutcome {
    try await purchase(productId: productId, billingPlanType: nil)
  }

  /// Purchase using StoreKit 2, optionally selecting a billing plan for products that expose multiple plans.
  ///
  /// For monthly subscriptions with a 12-month commitment, pass `.monthlyCommitment`.
  /// The default (`nil` / `.upFront`) keeps the existing StoreKit purchase behavior.
  public static func purchase(productId: String, billingPlanType: BillingPlanType?) async throws -> MiaMorePurchaseOutcome {
    let products = try await Product.products(for: [productId])
    guard let product = products.first else { throw MiaMorePurchaseError.productNotFound }

    guard let cfg = configuration else { throw SDKError.notConfigured }

    let result: Product.PurchaseResult
    switch billingPlanType ?? .upFront {
    case .upFront:
      result = try await product.purchase(options: [.appAccountToken(cfg.appAccountToken)])
    case .monthlyCommitment:
      #if MIAMORE_ENABLE_STOREKIT_COMMITMENT_PLANS
      if #available(iOS 26.4, macOS 26.4, tvOS 26.4, visionOS 26.4, *) {
        result = try await product.purchase(options: [.appAccountToken(cfg.appAccountToken), .billingPlanType(.monthly)])
      } else {
        throw MiaMorePurchaseError.unsupportedBillingPlanType
      }
      #else
      throw MiaMorePurchaseError.unsupportedBillingPlanType
      #endif
    case .unknown:
      throw MiaMorePurchaseError.unsupportedBillingPlanType
    }

    return try await handlePurchaseResult(result)
  }

  private static func handlePurchaseResult(_ result: Product.PurchaseResult) async throws -> MiaMorePurchaseOutcome {
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
