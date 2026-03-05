import Foundation

enum MiaMoreHTTP {
  static func buildURL(baseURL: URL, path: String, query: [URLQueryItem]) throws -> URL {
    var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    if comps == nil {
      comps = URLComponents(string: baseURL.absoluteString)
    }
    guard var c = comps else { throw MiaMoreSDK.SDKError.invalidBaseURL }

    let basePath = c.path
    let normalized = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
    c.path = normalized + path
    c.queryItems = query

    guard let url = c.url else { throw MiaMoreSDK.SDKError.invalidBaseURL }
    return url
  }

  static func decodeISODate(_ decoder: JSONDecoder) {
    decoder.dateDecodingStrategy = .custom { dec in
      let c = try dec.singleValueContainer()
      if c.decodeNil() { return Date(timeIntervalSince1970: 0) }
      let s = try c.decode(String.self)

      let f = ISO8601DateFormatter()
      f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let d = f.date(from: s) { return d }

      // fallback without fractional seconds
      let f2 = ISO8601DateFormatter()
      f2.formatOptions = [.withInternetDateTime]
      if let d2 = f2.date(from: s) { return d2 }

      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO date: \(s)")
    }
  }
}
