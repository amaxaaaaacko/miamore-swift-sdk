# MiaMore Swift SDK

Internal SDK for Appstero apps (Swift/iOS). It fetches **paywalls + products**, supports **purchases/restore** (StoreKit 2), and fetches **subscription status** from our backend.

> The SDK is **one library** shared across projects. You do **not** hardcode bundle ids per build. Each app uses its own `bundleId` and `apiKey` configured in AdminJS.

---

## Installation

### Swift Package Manager (recommended)

**Xcode:**
- *File → Add Packages…*
- URL: `https://github.com/amaxaaaaacko/miamore-swift-sdk`
- Version: `from 0.1.2`

**Package.swift:**

```swift
.package(url: "https://github.com/amaxaaaaacko/miamore-swift-sdk", from: "0.1.3"),
```

**Module / target name**
- Target: `miamore-swift-sdk`
- Module: `miamore_swift_sdk`

```swift
import miamore_swift_sdk
```

### CocoaPods

Not supported yet.

If you want this, we can ship a `podspec` that wraps the SwiftPM package.

### XCFramework

Not supported yet.

If you want this, we can add a GitHub Action to build and attach an XCFramework to Releases.

---

## Initialization

Call once at app launch (e.g. `AppDelegate` / `@main`):

```swift
import Foundation
import miamore_swift_sdk

let baseURL = URL(string: "https://<your-sdk-service>")!

await MainActor.run {
  MiaMoreSDK.configure(
    baseURL: baseURL,
    bundleId: Bundle.main.bundleIdentifier!,
    apiKey: "<sdk_api_key from AdminJS>",
    customerUserId: appsFlyerCustomerUserId,
    environment: .prod,
    logLevel: .info
  )
}
```

### Required parameters
- `baseURL` – our SDK config Cloud Run URL
- `bundleId` – app bundle id (must match `apps/{bundleId}`)
- `apiKey` – per-app SDK API key (generated in AdminJS). **Do not hard-code or commit it.**
- `customerUserId` – AppsFlyer-generated id (passed from app)

### Environment (PROD/SANDBOX)
Currently inferred server-side.
If you need explicit env switching in the SDK, we will add an optional `environment` parameter.

### Log level
Not implemented yet.
If needed, we can add `logLevel` and surface it to the underlying networking layer.

---

## Paywalls / Products

### Get paywall by placement (recommended)

```swift
let res = try await MiaMoreSDK.getPaywall(placement: "main")
let paywall = res.paywall

for p in paywall.products {
  print(p.productId)
}
```

### Get paywall by id / experiment id

```swift
let res = try await MiaMoreSDK.getPaywall(
  placement: nil,
  paywallId: "main_paywall_v1",
  experimentId: nil
)
```

### Get products for a paywall

The SDK returns `paywall.products` as an ordered list of product identifiers.
Use StoreKit to fetch `Product` objects.

---

## Purchases

Not implemented yet.

Planned API (StoreKit 2):
- `purchase(productId:)`
- `restore()`

---

## Profile / Subscription Status

### Fetch subscription status from our backend (fast)

This is designed to be independent from Adapty.

Server endpoint: `GET /v1/sdk/subscriptionStatus`.

> Requires that the user is linked to Apple `original_transaction_id`.

Planned SDK method:
- `getSubscriptionStatus()` → returns `{ expiresAt, isActive }`

**Current backend logic:** `isActive = expires_at > now`.

### Linking user to Apple original_transaction_id

To resolve subscription status by `customer_user_id`, the backend needs mapping:
`customer_user_id → original_transaction_id`.

Server endpoint: `POST /v1/sdk/link`.

SDK helper method is planned.

---

## Attribution

Not implemented yet.

Planned APIs:
- `setIntegrationIdentifier(appsflyerId:)`
- `updateAttribution(_:)`

---

## Callbacks / Errors

The SDK uses `async/await`.

Errors are thrown as `MiaMoreSDK.SDKError`:
- `notConfigured`
- `invalidBaseURL`
- `invalidResponse`
- `httpError(status:body:)`

---

## Threads / Concurrency

`MiaMoreSDK` is `@MainActor` (configuration is UI-safe).
Network calls are `async` and safe to call from any context.

---

## Info.plist / Capabilities

None required by this SDK.

(Your app will still need StoreKit entitlements / capabilities if you implement purchases.)

---

## Code Examples

### Full example

```swift
import Foundation
import miamore_swift_sdk

@MainActor
func boot(customerUserId: String) async {
  MiaMoreSDK.configure(
    baseURL: URL(string: "https://<your-sdk-service>")!,
    bundleId: Bundle.main.bundleIdentifier!,
    apiKey: "<sdk_api_key>",
    customerUserId: customerUserId
  )

  do {
    let res = try await MiaMoreSDK.getPaywall(placement: "main")
    print("Paywall:", res.paywall.paywallId)
  } catch {
    print("SDK error:", error)
  }
}
```

### Optional: Adapty identity sync

If the app includes Adapty:

```swift
#if canImport(Adapty)
try await MiaMoreAdaptyBridge.identify(customerUserId: appsFlyerCustomerUserId)
#endif
```
