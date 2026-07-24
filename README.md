# MiaMore Swift SDK

Internal Swift/iOS SDK. It fetches **paywalls + products**, supports **purchases/restore** (StoreKit 2), and fetches **subscription status** from your backend.

## Documentation

- [Quick start](#installation)
- [Paywalls / Products](#paywalls--products)
- [Purchases](#purchases)
- [Profile / Subscription Status](#profile--subscription-status)
- [Firebase / Google Analytics](#firebase--google-analytics)
- [Monthly subscriptions with a 12-month commitment](docs/monthly-commitment-subscriptions.md)
- [Web payments](docs/web-payments.md)

> The SDK is **one library** shared across projects. You do **not** hardcode bundle ids per build. Each app uses its own `bundleId` and `apiKey` configured in AdminJS.

---

## Installation

### Swift Package Manager (recommended)

**Xcode:**
- *File → Add Packages…*
- URL: `https://github.com/amaxaaaaacko/miamore-swift-sdk`
- Version: `from 0.1.7`

**Package.swift:**

```swift
.package(url: "https://github.com/amaxaaaaacko/miamore-swift-sdk", from: "0.1.7"),
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
- `baseURL` – your SDK service base URL
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
  print(p.billingPlanType?.rawValue ?? "default")
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

For a yearly App Store product that has both normal annual billing and monthly billing with a 12-month commitment, AdminJS/backend can return the same `product_id` more than once with different `billing_plan_type` values:

```json
[
  { "product_id": "com.example.pro.yearly", "billing_plan_type": "up_front", "sort": 1 },
  { "product_id": "com.example.pro.yearly", "billing_plan_type": "monthly", "sort": 2 }
]
```

Supported billing plan values in the SDK:
- `.upFront` / JSON `"up_front"` — standard up-front billing
- `.monthlyCommitment` / JSON `"monthly"` — monthly billing with a 12-month commitment

---

## Purchases

StoreKit 2 APIs:
- `purchase(productId:)`
- `purchase(productId:billingPlanType:)`
- `restore()`

Standard purchase:

```swift
let outcome = try await MiaMoreSDK.purchase(productId: "com.example.pro.yearly")
```

Monthly billing with a 12-month commitment:

```swift
let outcome = try await MiaMoreSDK.purchase(
  productId: "com.example.pro.yearly",
  billingPlanType: .monthlyCommitment
)
```

This uses Apple StoreKit's `Product.PurchaseOption.billingPlanType(.monthly)`.
Starting with SDK `v0.1.8`, the package manifest enables `MIAMORE_ENABLE_STOREKIT_COMMITMENT_PLANS` automatically when the installed Apple SDK exposes StoreKit's billing-plan purchase option. Apps do not need to add that active compilation condition manually; app-target flags do not affect Swift Package targets.

Because the StoreKit billing-plan symbol requires Xcode 26.5 SDK or newer, older Apple SDKs keep compiling the package without the commitment purchase path; in that case requesting `.monthlyCommitment` still throws `MiaMorePurchaseError.unsupportedBillingPlanType`. Existing apps pinned to older SDK tags are not affected by this release.

Normal `.upFront` purchases keep the existing StoreKit purchase behavior.

---

## Profile / Subscription Status

### Fetch subscription status from our backend (fast)

This is designed to be independent from Adapty.

Server endpoint: `GET /v1/sdk/subscriptionStatus`.

> Requires that the user is linked to Apple `original_transaction_id`.

SDK method:
- `getSubscriptionStatus()` → returns `expiresAt`, `isActive`, `source`, `provider`, `currentSubscriptionStatus`, `billingPlanType`, optional `commitment` details, and web payment fields when entitlement comes from Stripe/Solidgate.

**Current backend logic:** `isActive = expires_at > now`, except terminal/problem statuses such as billing retry, refund, or expiration are treated as inactive.

### Linking user to Apple original_transaction_id

To resolve subscription status by `customer_user_id`, the backend needs mapping:
`customer_user_id → original_transaction_id`.

Server endpoint: `POST /v1/sdk/link`.

SDK helper method: `link(originalTransactionId:environment:)`.

---

## Attribution

Use attribution helpers to send third-party installation identifiers to the backend.

### AppsFlyer

```swift
try await MiaMoreSDK.setIntegrationIdentifier(appsflyerId: appsFlyerCustomerUserId)
```

### Firebase / Google Analytics

If the app uses Firebase Analytics, send the Firebase App Instance ID once on every app launch after:

1. `FirebaseApp.configure()`
2. `MiaMoreSDK.configure(...)`

Do this before any purchase flow, otherwise server-side subscription events cannot be attached to the Firebase installation.

```swift
import FirebaseCore
import FirebaseAnalytics
import miamore_swift_sdk

FirebaseApp.configure()

await MainActor.run {
  MiaMoreSDK.configure(
    baseURL: URL(string: "https://<your-sdk-service>")!,
    bundleId: Bundle.main.bundleIdentifier!,
    apiKey: "<sdk_api_key>",
    customerUserId: appsFlyerCustomerUserId
  )
}

if let firebaseAppInstanceId = Analytics.appInstanceID() {
  try await MiaMoreSDK.setIntegrationIdentifier(firebaseAppInstanceId: firebaseAppInstanceId)
}
```

The SDK intentionally does not depend on Firebase. The host app owns Firebase setup and passes the resulting App Instance ID into MiaMore.

- `setIntegrationIdentifier(appsflyerId:)`
- `setIntegrationIdentifier(firebaseAppInstanceId:)`
- `updateAttribution(appsflyerId:firebaseAppInstanceId:payload:)`

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
