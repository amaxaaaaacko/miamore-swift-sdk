import Foundation
import Testing
@testable import miamore_swift_sdk

@Suite struct BuildURLTests {
  @Test func appendsPathToBareHost() throws {
    let url = try MiaMoreHTTP.buildURL(
      baseURL: URL(string: "https://api.test")!,
      path: "/v1/sdk/paywall",
      query: [URLQueryItem(name: "bundleId", value: "com.example.app")]
    )
    #expect(url.absoluteString == "https://api.test/v1/sdk/paywall?bundleId=com.example.app")
  }

  @Test func keepsBasePathAndDropsItsTrailingSlash() throws {
    let url = try MiaMoreHTTP.buildURL(
      baseURL: URL(string: "https://api.test/prefix/")!,
      path: "/v1/sdk/link",
      query: [URLQueryItem(name: "a", value: "1")]
    )
    #expect(url.absoluteString == "https://api.test/prefix/v1/sdk/link?a=1")
  }

  /// Current behavior: an empty query still leaves a trailing `?` (every POST endpoint passes `query: []`).
  @Test func emptyQueryLeavesTrailingQuestionMark() throws {
    let url = try MiaMoreHTTP.buildURL(baseURL: URL(string: "https://api.test")!, path: "/v1/sdk/link", query: [])
    #expect(url.absoluteString == "https://api.test/v1/sdk/link?")
  }

  @Test func percentEncodesQueryValues() throws {
    let url = try MiaMoreHTTP.buildURL(
      baseURL: URL(string: "https://api.test")!,
      path: "/v1/sdk/paywall",
      query: [URLQueryItem(name: "placement", value: "on boarding&x")]
    )
    #expect(url.absoluteString == "https://api.test/v1/sdk/paywall?placement=on%20boarding%26x")
  }
}
