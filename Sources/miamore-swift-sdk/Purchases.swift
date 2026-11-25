import Foundation

#if canImport(StoreKit)
import StoreKit

@MainActor
private var miaMoreTransactionUpdatesTask: Task<Void, Never>?

public enum MiaMorePurchaseOutcome: Sendable {
  case success(transactionId: String, originalTransactionId: String, productId: String)
  case pending
  case userCancelled
}

public enum MiaMorePurchaseError: Error {
  case productNotFound
  case failedVerification
  /// The requested billing plan requires StoreKit commitment-plan symbols/runtime support.
  /// SDK v0.1.8+ enables those symbols in the package target; use Xcode 26.5 SDK or newer.
  case unsupportedBillingPlanType
}

extension MiaMoreSDK {
  /// Starts, once per process, the `Transaction.updates` listener and a pass over `Transaction.unfinished`.
  ///
  /// The unfinished pass retries transactions whose link failed earlier (see `linkThenFinish`). The listener is
  /// started first so no update is missed while that pass runs; a transaction seen by both is linked twice,
  /// which the backend already tolerates (`restore()` re-links every entitlement).
  static func startTransactionUpdatesListenerIfNeeded() {
    guard miaMoreTransactionUpdatesTask == nil else { return }

    miaMoreTransactionUpdatesTask = Task {
      for await update in Transaction.updates {
        await linkThenFinishIfVerified(update)
      }
    }

    Task {
      for await unfinished in Transaction.unfinished {
        await linkThenFinishIfVerified(unfinished)
      }
    }
  }

  /// Unverified transactions are left untouched, as before.
  private static func linkThenFinishIfVerified(_ result: VerificationResult<Transaction>) async {
    guard case .verified(let transaction) = result else { return }
    await linkThenFinish(originalTransactionId: String(transaction.originalID)) {
      await transaction.finish()
    }
  }

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
      // The purchase succeeded either way; a failed link is retried on the next launch.
      await linkThenFinish(originalTransactionId: String(transaction.originalID)) {
        await transaction.finish()
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
