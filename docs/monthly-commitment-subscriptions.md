# Monthly subscriptions with a 12-month commitment

This page explains how to use MiaMore Swift SDK with Apple's monthly subscriptions that have a 12-month commitment.

Apple calls this a monthly subscription with a 12-month commitment. In our SDK/API we expose it as `monthlyCommitment` / `billing_plan_type: "monthly"`.

---

## What this subscription type is

A monthly subscription with a 12-month commitment is configured on an existing yearly auto-renewable subscription in App Store Connect.

Important details:

- It is not a new App Store product type.
- The App Store product id stays the same as the yearly subscription product id.
- The customer pays every month.
- The customer commits to 12 monthly billing periods.
- Canceling during the commitment disables the next 12-month commitment renewal, but billing continues for the remaining months in the current commitment.

Example:

```text
Product id: com.example.pro.yearly

Plan A: up-front annual billing
Plan B: monthly billing with 12-month commitment
```

Both plans can use the same product id. The difference is the billing plan selected at purchase time.

---

## Availability

Apple currently requires:

- Xcode 26.5 SDK or newer to compile the StoreKit billing-plan purchase option.
- iOS 26.4, iPadOS 26.4, macOS 26.4, tvOS 26.4, or visionOS 26.4 or newer on device.
- The feature is not available in the United States and Singapore.

MiaMore Swift SDK keeps compatibility with older Xcode versions. The public API is available, but actual monthly-commitment purchasing is compiled only when this Swift active compilation condition is enabled:

```text
MIAMORE_ENABLE_STOREKIT_COMMITMENT_PLANS
```

Without that flag, calling `.monthlyCommitment` throws:

```swift
MiaMorePurchaseError.unsupportedBillingPlanType
```

Normal up-front purchases continue to work without the flag.

---

## App Store Connect setup

In App Store Connect:

1. Open the yearly auto-renewable subscription product.
2. Enable the monthly billing plan for that yearly product.
3. Configure the monthly price per territory.
4. Review upgrade/downgrade ordering inside the subscription group.

The same product id will now have two billing options:

- `upFront` / `BILLED_UPFRONT` — normal yearly subscription billed up front.
- `monthly` / `MONTHLY` — monthly billing with a 12-month commitment.

---

## Paywall configuration

Because both billing options can share the same product id, the paywall may include the same `product_id` multiple times with different `billing_plan_type` values.

Example backend/AdminJS paywall product list:

```json
[
  {
    "product_id": "com.example.pro.yearly",
    "billing_plan_type": "up_front",
    "sort": 1,
    "title": "Annual",
    "subtitle": "Pay once per year"
  },
  {
    "product_id": "com.example.pro.yearly",
    "billing_plan_type": "monthly",
    "sort": 2,
    "title": "Monthly",
    "subtitle": "12-month commitment, billed monthly",
    "badge": "Best price monthly"
  }
]
```

The Swift SDK decodes this into:

```swift
for ref in paywall.products {
  print(ref.productId)
  print(ref.billingPlanType ?? .upFront)
}
```

Supported SDK values:

```swift
MiaMoreSDK.BillingPlanType.upFront
MiaMoreSDK.BillingPlanType.monthlyCommitment
```

Unknown/future values decode as `.unknown` so the app can fail gracefully instead of crashing.

---

## Fetching StoreKit products

The SDK returns product refs, not StoreKit `Product` objects.

If a paywall contains duplicated product ids for multiple billing plans, fetch unique StoreKit products:

```swift
let refs = paywall.products
let productIds = Array(Set(refs.map(\.productId)))
let products = try await Product.products(for: productIds)
let productsById = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
```

Render paywall rows/buttons from `paywall.products`, and look up the StoreKit product by `productId`.

---

## Display requirements

For the monthly commitment plan, Apple requires the app to show both:

- the monthly billing price
- the total commitment amount

Use StoreKit's `pricingTerms` for the selected product to find the monthly billing plan and its commitment info.

Conceptually:

```swift
if let terms = product.subscription?.pricingTerms.first(where: { $0.billingPlanType == .monthly }) {
  let monthlyPrice = terms.billingDisplayPrice
  let totalCommitmentPrice = terms.commitmentInfo.price

  // Display both values before purchase.
}
```

Because these StoreKit properties require Xcode 26.5 SDK or newer, keep this UI behind the same availability/toolchain strategy as purchase.

---

## Purchase flow

Standard up-front purchase:

```swift
let outcome = try await MiaMoreSDK.purchase(
  productId: "com.example.pro.yearly",
  billingPlanType: .upFront
)
```

Monthly billing with a 12-month commitment:

```swift
let outcome = try await MiaMoreSDK.purchase(
  productId: "com.example.pro.yearly",
  billingPlanType: .monthlyCommitment
)
```

Under the hood, the monthly commitment path uses Apple's StoreKit option:

```swift
product.purchase(options: [.billingPlanType(.monthly)])
```

If you call the old API, behavior is unchanged:

```swift
let outcome = try await MiaMoreSDK.purchase(productId: "com.example.pro.yearly")
```

This uses StoreKit's default up-front billing behavior.

---

## Subscription status response

`getSubscriptionStatus()` now includes billing plan and commitment details when available:

```swift
let status = try await MiaMoreSDK.getSubscriptionStatus()

print(status.isActive)
print(status.expiresAt)                 // current billing period expiration
print(status.billingPlanType)           // .upFront / .monthlyCommitment / .unknown / nil
print(status.commitment?.expirationDate) // full commitment expiration, display only
print(status.commitment?.billingPeriodNumber)
print(status.commitment?.totalBillingPeriods)
print(status.commitment?.autoRenewStatus)
```

Important:

- Use `expiresAt` / `isActive` for access decisions.
- Use `commitment.expirationDate` only for displaying commitment progress.
- Do not grant access until the full commitment expiration date. Each monthly billing period produces its own transaction and entitlement window.

---

## Cancellation behavior

For a normal up-front subscription, cancellation usually means the subscription will not renew after the current paid period.

For monthly billing with a 12-month commitment, cancellation during the commitment means:

- The current 12-month commitment continues.
- Monthly billing continues for the remaining billing periods.
- The customer disables renewal into the next 12-month commitment.

Backend nuance:

- For `billingPlanType == MONTHLY`, renewal-status changes are interpreted using commitment auto-renew status, not only the standard subscription auto-renew status.
- The app should continue to rely on `isActive` from `/v1/sdk/subscriptionStatus`.

---

## Billing issues

Apple says Billing Grace Period does not apply to monthly subscriptions with a 12-month commitment.

Backend behavior:

- `DID_FAIL_TO_RENEW` for `MONTHLY` billing is stored as `billing_retry`.
- `isActive` returns `false` for `billing_retry`, even if the previous `expires_at` is still in the future.
- `DID_RENEW` with billing recovery restores access when Apple sends a new valid transaction.

App behavior:

- Always refresh subscription status after purchase/restore and on app foreground.
- Treat `isActive` as the source of truth.

---

## Refunds

Refund behavior depends on which billing period is refunded:

- Refund for a previous billing period: that specific transaction is revoked; commitment may continue.
- Refund for the current billing period: commitment can end immediately and access should be revoked.

The SDK/backend status endpoint abstracts the active/inactive decision through `isActive`.

---

## Offers

Introductory offers, promotional offers, win-back offers, and offer codes are specific to the billing plan.

When building paywall UI with StoreKit 26.5+, read offers from the selected pricing term, not globally from the product.

Conceptually:

```swift
let monthlyTerms = product.subscription?.pricingTerms.first {
  $0.billingPlanType == .monthly
}

let offersForMonthlyCommitment = monthlyTerms?.subscriptionOffers
```

---

## Testing checklist

Use StoreKit Testing in Xcode 26.5+:

- Configure the yearly subscription product.
- Add monthly billing plan type.
- Confirm the paywall shows two options for the same product id.
- Confirm the monthly commitment option displays both monthly and total commitment price.
- Confirm `.monthlyCommitment` purchase succeeds on supported OS.
- Confirm restore links the original transaction id.
- Confirm `getSubscriptionStatus()` returns:
  - `billingPlanType == .monthlyCommitment`
  - current-period `expiresAt`
  - optional `commitment` details
- Simulate cancellation and confirm access remains active for remaining paid periods.
- Simulate billing issue and confirm `isActive == false` while in billing retry.
- Simulate billing recovery and confirm access restores.

---

## Common mistakes

### Mistake: Creating a second product id for the monthly commitment plan

Do not do this unless the business intentionally wants a separate product. Apple's commitment billing plan is configured on the existing yearly subscription product.

### Mistake: Using commitment expiration for access

Wrong:

```swift
// Do not use commitment expiration to grant access.
status.commitment?.expirationDate
```

Right:

```swift
status.isActive
status.expiresAt
```

### Mistake: Treating cancellation as immediate churn

For commitment plans, cancellation disables the next commitment renewal; it does not necessarily end the current 12-month commitment.

### Mistake: Fetching duplicate StoreKit products

Paywall refs may contain duplicate product ids. Fetch unique StoreKit product ids, but render each paywall ref as its own UI option.

---

## Minimal app-side pattern

```swift
let res = try await MiaMoreSDK.getPaywall(placement: "main")
let refs = res.paywall.products

for ref in refs {
  switch ref.billingPlanType ?? .upFront {
  case .upFront:
    // Render normal annual option.
    break
  case .monthlyCommitment:
    // Render monthly commitment option.
    // Show monthly price + total commitment amount using StoreKit pricingTerms.
    break
  case .unknown:
    // Hide or disable unknown future billing plan.
    break
  }
}

func buy(_ ref: MiaMoreSDK.ProductRef) async throws {
  let outcome = try await MiaMoreSDK.purchase(
    productId: ref.productId,
    billingPlanType: ref.billingPlanType
  )

  switch outcome {
  case .success:
    let status = try await MiaMoreSDK.getSubscriptionStatus()
    // Unlock based on status.isActive.
    print(status.isActive)
  case .pending:
    break
  case .userCancelled:
    break
  }
}
```
