# miamore-swift-sdk

Internal Swift SDK for Appstero apps.

## Install (Swift Package Manager)

In Xcode:
- File → Add Packages...
- URL: `https://github.com/amaxaaaaacko/miamore-swift-sdk`

Or in `Package.swift`:

```swift
.package(url: "https://github.com/amaxaaaaacko/miamore-swift-sdk", from: "0.1.0"),
```

## Usage

```swift
import Foundation
import miamore_swift_sdk

// baseURL = Cloud Run service for SDK config API
let baseURL = URL(string: "https://appstore-sdk-ztkt56mq6a-uc.a.run.app")!

MiaMoreSDK.configure(
  baseURL: baseURL,
  bundleId: Bundle.main.bundleIdentifier!,
  apiKey: "<sdk_api_key from AdminJS>",
  customerUserId: appsFlyerCustomerUserId
)

let response = try await MiaMoreSDK.getPaywall(placement: "main")
print(response.paywall.products)
```

### Adapty identity sync (optional)

If your app includes the Adapty SDK, you can align identities:

```swift
#if canImport(Adapty)
try await MiaMoreAdaptyBridge.identify(customerUserId: appsFlyerCustomerUserId)
#endif
```

## Backend contract

SDK calls:

`GET /v1/sdk/paywall?bundleId=...&customerUserId=...&placement=...`

with header:

`Authorization: Bearer <sdk_api_key>`
