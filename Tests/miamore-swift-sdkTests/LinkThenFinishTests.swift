import Foundation
import Testing
@testable import miamore_swift_sdk

extension BackendRequestTests {
  /// A purchase must be linked before StoreKit is told it is finished: a finished transaction is never
  /// delivered again, so a failed link would be lost for good.
  @MainActor @Suite struct LinkThenFinish {
    private static let linkPath = "/v1/sdk/link"
    private static let transactionId = "2000000123"

    /// Runs `linkThenFinish` against a canned `link` answer and reports whether `finish` was called.
    private static func run(linkStatus: Int) async -> (finished: Bool, returned: Bool) {
      StubbedSDK.configure(responses: [linkPath: (linkStatus, "{}")])
      var finished = false
      let returned = await MiaMoreSDK.linkThenFinish(originalTransactionId: transactionId) { finished = true }
      return (finished, returned)
    }

    @Test func linksTheTransactionThenFinishesIt() async throws {
      let outcome = await Self.run(linkStatus: 200)

      #expect(outcome.finished)
      #expect(outcome.returned)
      let request = try #require(StubURLProtocol.requestsExceptAppOpen.first)
      #expect(request.path == Self.linkPath)
      #expect(request.body["originalTransactionId"] as? String == Self.transactionId)
    }

    @Test func offlineLeavesTheTransactionUnfinishedForRetry() async {
      let outcome = await Self.run(linkStatus: StubURLProtocol.offlineStatus)

      #expect(!outcome.finished)
      #expect(!outcome.returned)
    }

    @Test(arguments: [500, 502, 503, 408, 429])
    func retryableBackendFailureLeavesTheTransactionUnfinished(status: Int) async {
      let outcome = await Self.run(linkStatus: status)

      #expect(!outcome.finished)
      #expect(!outcome.returned)
    }

    /// A retry would fail the same way, and an unfinished transaction would come back on every launch.
    @Test(arguments: [400, 401, 403, 404, 409, 422])
    func permanentBackendFailureStillFinishesTheTransaction(status: Int) async {
      let outcome = await Self.run(linkStatus: status)

      #expect(outcome.finished)
      #expect(outcome.returned)
    }
  }
}
