# Web payments

MiaMore Swift SDK can unlock users who paid on the web through Stripe or Solidgate.

The app does not talk to Stripe or Solidgate directly. The backend receives provider webhooks, normalizes the subscription, and `getSubscriptionStatus()` returns the active entitlement.

---

## Required identity

The web checkout must pass the same customer id used by the SDK:

```swift
MiaMoreSDK.configure(
  bundleId: "com.example.app",
  customerUserId: appsflyerIdOrInternalUserId,
  apiKey: "..."
)
```

Web checkout metadata should include:

```json
{
  "customer_user_id": "<same customerUserId>",
  "bundle_id": "com.example.app"
}
```

Supported metadata aliases:

- `customer_user_id`
- `customerUserId`
- `appsflyer_id`
- `appsflyerId`
- `miamore_customer_user_id`

For Stripe Checkout, `client_reference_id` is also accepted as a fallback.

---

## Reading status

Use the existing API:

```swift
let status = try await MiaMoreSDK.getSubscriptionStatus()

if status.isActive {
  // unlock premium
}
```

For App Store subscriptions:

```swift
status.source                // .appStore or nil on older backend
status.originalTransactionId
status.billingPlanType
status.commitment
```

For web subscriptions:

```swift
status.source                // .web
status.provider              // .stripe / .solidgate
status.providerAccountId     // Stripe account id from backend config, if Stripe
status.providerChannelId     // Solidgate channel id from backend config, if Solidgate
status.providerSubscriptionId
status.productId
status.priceId
status.entitlementId
status.trialType             // free_trial / paid_trial / none / unknown
status.expiresAt
```

Always unlock from:

```swift
status.isActive
```

Do not branch entitlement access only on App Store fields, because web-only subscriptions do not have an Apple `originalTransactionId`.

---

## Example

```swift
let status = try await MiaMoreSDK.getSubscriptionStatus()

switch status.source {
case .appStore:
  print("App Store subscription", status.productId ?? "")
case .web:
  print("Web subscription", status.provider?.rawValue ?? "unknown")
  print(status.providerSubscriptionId ?? "")
case .unknown, nil:
  break
}

if status.isActive {
  unlockPremium()
}
```

---

## Backend behavior

Backend checks both:

1. App Store subscription linked by `original_transaction_id`.
2. Web subscriptions linked by `customer_user_id`.

If web is active and App Store is inactive/missing, backend returns `source: "web"`.

If both are active, App Store remains primary, but web provider fields may still be included for observability.
