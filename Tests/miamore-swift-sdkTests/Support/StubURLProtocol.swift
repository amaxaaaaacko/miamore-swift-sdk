import Foundation
@testable import miamore_swift_sdk

/// A request the SDK sent, as `StubURLProtocol` saw it.
struct RecordedRequest: @unchecked Sendable {
  let url: URL
  let method: String
  let headers: [String: String]
  let body: [String: Any]

  var path: String { url.path }

  var query: [String: String] {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
  }
}

/// Answers MiaMore SDK requests from canned responses keyed by path, and records the requests.
///
/// `URLProtocol` loads on a background thread while the auto app-open tracker may fire at any time,
/// so all shared state goes through `lock`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
  typealias CannedResponse = (status: Int, json: String)

  static let host = "stub.miamore.test"
  static let appOpenPath = "/v1/sdk/appOpen"

  private static let lock = NSLock()
  nonisolated(unsafe) private static var cannedResponses: [String: CannedResponse] = [:]
  nonisolated(unsafe) private static var recordedRequests: [RecordedRequest] = []

  /// Registers the stub, clears recorded requests and sets the responses (unknown paths answer `404 {}`).
  static func install(responses: [String: CannedResponse]) {
    URLProtocol.registerClass(StubURLProtocol.self)
    lock.withLock {
      cannedResponses = responses
      recordedRequests = []
    }
  }

  static var requests: [RecordedRequest] {
    lock.withLock { recordedRequests }
  }

  /// `configure()` fires a background `appOpen`; most tests only look at the calls under test.
  static var requestsExceptAppOpen: [RecordedRequest] {
    requests.filter { $0.path != appOpenPath }
  }

  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    let recorded = RecordedRequest(
      url: url,
      method: request.httpMethod ?? "GET",
      headers: request.allHTTPHeaderFields ?? [:],
      body: Self.jsonBody(of: request)
    )
    let canned = Self.lock.withLock {
      Self.recordedRequests.append(recorded)
      return Self.cannedResponses[url.path]
    }
    let (status, json) = canned ?? (404, "{}")

    let headers = ["Content-Type": "application/json"]
    guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(json.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  /// `URLSession` hands a protocol the body as a stream, not as `httpBody`.
  private static func jsonBody(of request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody ?? request.httpBodyStream.map(readAll) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
  }

  private static func readAll(_ stream: InputStream) -> Data {
    let chunkSize = 4096
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: chunkSize)
    stream.open()
    defer { stream.close() }
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: chunkSize)
      guard count > 0 else { break }
      data.append(buffer, count: count)
    }
    return data
  }
}

/// SDK configuration shared by the network tests.
@MainActor
enum StubbedSDK {
  static let baseURL = URL(string: "https://\(StubURLProtocol.host)")!
  static let bundleId = "com.example.app"
  static let apiKey = "sdk_key"
  static let customerUserId = "device-1"
  static let appAccountToken = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!

  static func configure(
    environment: MiaMoreEnvironment = .prod,
    responses: [String: StubURLProtocol.CannedResponse] = [:]
  ) {
    StubURLProtocol.install(responses: responses)
    MiaMoreSDK.configure(
      baseURL: baseURL,
      bundleId: bundleId,
      apiKey: apiKey,
      customerUserId: customerUserId,
      appAccountToken: appAccountToken,
      environment: environment
    )
  }
}
