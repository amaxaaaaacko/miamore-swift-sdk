import Foundation

#if canImport(UIKit)
import UIKit
#endif

@MainActor
extension MiaMoreSDK {
  struct AppOpenBody: Codable, Sendable {
    let bundleId: String
    let customerUserId: String
    let openedAt: String
    let tzOffsetMin: Int

    enum CodingKeys: String, CodingKey {
      case bundleId
      case customerUserId
      case openedAt
      case tzOffsetMin
    }
  }

  /// Manually track a basic app open event.
  ///
  /// Note: the SDK also auto-tracks this (1 event per ~30 minutes) after `configure()`.
  public static func trackAppOpen() async throws {
    guard let cfg = configuration else { throw SDKError.notConfigured }

    let url = try MiaMoreHTTP.buildURL(baseURL: cfg.baseURL, path: "/v1/sdk/appOpen", query: [])

    let tzOffsetMin = TimeZone.current.secondsFromGMT() / 60
    let body = AppOpenBody(
      bundleId: cfg.bundleId,
      customerUserId: cfg.customerUserId,
      openedAt: ISO8601DateFormatter().string(from: Date()),
      tzOffsetMin: tzOffsetMin
    )

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    req.httpBody = try JSONEncoder().encode(body)

    let (data, resp) = try await URLSession.shared.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw SDKError.invalidResponse }

    if http.statusCode >= 300 {
      let body = String(data: data, encoding: .utf8)
      throw SDKError.httpError(status: http.statusCode, body: body)
    }
  }
}

// MARK: - Auto tracking

@MainActor
final class MiaMoreAppOpenAutoTracker {
  static let shared = MiaMoreAppOpenAutoTracker()

  private let userDefaults = UserDefaults.standard
  private var started = false

  /// 30 minutes.
  private let minInterval: TimeInterval = 30 * 60

  private init() {}

  func startIfNeeded() {
    guard !started else { return }
    started = true

    #if canImport(UIKit)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onDidBecomeActive),
      name: UIApplication.didBecomeActiveNotification,
      object: nil
    )
    #endif

    // fire once on start
    Task { await self.sendIfNeeded() }
  }

  @objc private func onDidBecomeActive() {
    Task { await self.sendIfNeeded() }
  }

  private func key(bundleId: String) -> String {
    "miamore.lastAppOpenSentAt.\(bundleId)"
  }

  private func shouldSend(bundleId: String, now: Date) -> Bool {
    let k = key(bundleId: bundleId)
    let last = userDefaults.double(forKey: k)
    if last <= 0 { return true }
    return now.timeIntervalSince1970 - last >= minInterval
  }

  private func markSent(bundleId: String, now: Date) {
    userDefaults.set(now.timeIntervalSince1970, forKey: key(bundleId: bundleId))
  }

  private func sendIfNeeded() async {
    guard let cfg = MiaMoreSDK.configuration else { return }

    let now = Date()
    guard shouldSend(bundleId: cfg.bundleId, now: now) else { return }

    // Mark before network call to avoid duplicate bursts.
    markSent(bundleId: cfg.bundleId, now: now)

    do {
      try await MiaMoreSDK.trackAppOpen()
    } catch {
      // If it fails, allow retry on next becomeActive by rolling back the timestamp.
      // (This is conservative: we prefer not losing the event.)
      userDefaults.removeObject(forKey: key(bundleId: cfg.bundleId))

      if cfg.logLevel == .debug {
        print("[MiaMore] appOpen tracking failed: \(error)")
      }
    }
  }
}
