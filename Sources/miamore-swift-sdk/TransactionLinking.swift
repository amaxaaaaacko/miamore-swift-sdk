import Foundation

extension MiaMoreSDK {
  private static let retryableHTTPStatuses: Set<Int> = [408, 429]
  private static let firstServerErrorStatus = 500

  /// Links a verified transaction to this customer, then finishes it.
  ///
  /// StoreKit never delivers a finished transaction again, so finishing first would lose the link for good
  /// whenever the request failed. When linking fails for a reason a retry can fix (offline, timeout, 5xx),
  /// the transaction is left unfinished: StoreKit keeps it in `Transaction.unfinished` and the SDK links it
  /// again on the next `configure()`. Any other failure finishes it anyway, because a retry would fail the
  /// same way and the transaction would come back on every launch.
  ///
  /// - Returns: whether `finish` was called.
  @discardableResult
  static func linkThenFinish(originalTransactionId: String, finish: () async -> Void) async -> Bool {
    do {
      try await link(originalTransactionId: originalTransactionId)
    } catch let error where isRetryableLinkFailure(error) {
      return false
    } catch {
      // Not retryable: finishing is safer than replaying the transaction forever.
    }
    await finish()
    return true
  }

  static func isRetryableLinkFailure(_ error: Error) -> Bool {
    switch error {
    case is URLError:
      return true
    case SDKError.httpError(let status, _):
      return status >= firstServerErrorStatus || retryableHTTPStatuses.contains(status)
    default:
      return false
    }
  }
}
