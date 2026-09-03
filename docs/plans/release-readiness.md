---
slug: release-readiness
status: draft
created: 2026-09-02
design: M7 — Release readiness
covers: [R29, R33, R34, R39, R41]
format: pseudocode
---

# Release readiness — Plan

## Summary

The last mile: the real AdMob provider with the non-personalised flag and the
regional consent flow behind the protocol, the privacy policy link, live
WeatherKit on a signed device with the horizon confirmed, the accessibility
pass, the edge-case copy pass, TestFlight, and the App Store listing with the
health disclaimer and privacy labels.

Non-goals:
- We do NOT add personalised ads, a tracking prompt, or any identifier.
- We do NOT add features; every screen exists after M6.

Owner costs:
- Apple Developer Program membership; WeatherKit capability; AdMob account and app id; a privacy policy page URL; confirming Google's EEA/UK consent requirement; TestFlight testers; S8 (live), S9, S12, S13, S16 on a device.

Rulings: D-2026-09-03-F1 (docs/DECISIONS.md); design revisions 1 and 3 for ads and consent

## The slices

## Slice 1 — The AdMob provider, non-personalised, with regional consent

- **Delivers:** `AdMobBannerProvider` conforms to `AdBannerProvider`, sets the non-personalised flag before any request, runs Google's consent flow once where the region requires it and serves limited ads on refusal, and is injected in release builds only; the no-op stays in tests and previews; S15's recorded-request assertion passes.
- **Files:** `Sources/IcarusAds/AdBannerProvider.swift`, `Sources/IcarusAds/NoAdsProvider.swift`, `Sources/IcarusAds/AdMobBannerProvider.swift`, `Sources/IcarusAds/ConsentFlow.swift`, `Tests/IcarusAdsTests/AdMobConfigurationTests.swift`, `Package.swift`, `App/AppEnvironment.swift`, `acceptance/S15-ads.sh`
- **Estimate:** ~360 lines

### Signatures

```text
public protocol AdBannerProvider: Sendable {
    func prepare(region: ConsentRegion) async -> AdReadiness       // runs consent if required; idempotent
    @MainActor func banner(width: CGFloat) -> AnyView?              // nil for NoAdsProvider
    var requestConfiguration: AdRequestConfiguration { get }       // inspectable: nonPersonalised == true always
}
public enum ConsentRegion: Sendable, Equatable { case requiresConsent, none }
public enum AdReadiness: Sendable, Equatable { case ready, limited, unavailable }
public struct AdRequestConfiguration: Sendable, Equatable { public let nonPersonalised: Bool; public let consentShown: Bool }
public struct NoAdsProvider: AdBannerProvider { public init() }
public final class AdMobBannerProvider: AdBannerProvider { public init(adUnitID: String) }   // Google Mobile Ads SDK + UMP behind `#if canImport(GoogleMobileAds)`
// Package.swift: IcarusAds adds the Google Mobile Ads SPM dependency pinned exact; IcarusUI depends on IcarusAds for the protocol only
// Promises (S15): requestConfiguration.nonPersonalised == true before the first banner(); prepare(.requiresConsent) shows the consent flow once and .limited on refusal; NoAdsProvider.banner == nil; no GoogleMobileAds import outside Sources/IcarusAds
```

### Internals

```text
AdMobBannerProvider.prepare: if region == .requiresConsent → UMPConsentInformation.requestConsentInfoUpdate → present form if required → map status to .ready/.limited; set GADMobileAds.sharedInstance() extras npa=1 on every GADRequest (GADExtras "npa": "1"); store consentShown in ProfileFlags
banner(width): GADBannerView adaptive anchored size for width; UIViewRepresentable wrapper
ConsentRegion decided by UMP itself (geography); the app passes .requiresConsent when the SDK reports consent required; Settings offers "Privacy options" to re-open the form where required (UMP privacy options requirement)
acceptance/S15-ads.sh: `swift test --filter IcarusAdsTests` + grep for GoogleMobileAds imports outside Sources/IcarusAds
```

## Slice 2 — Live WeatherKit, entitlement, attribution, privacy policy

- **Delivers:** The app target carries the WeatherKit capability and the attribution view with Apple's logo and legal link findable from every tab; the privacy policy link in Settings opens the owner's page; the live fetch on a signed device matches the built-in Weather app for the same hour and the returned horizon is recorded in Tunables (S8 owner part).
- **Files:** `project.yml`, `App/ProjectIcarus.entitlements`, `Sources/IcarusUI/Settings/PrivacyPolicyLink.swift`, `App/AppEnvironment.swift`, `Sources/IcarusCore/Tunables.swift`, `docs/reviews/citations.md`
- **Estimate:** ~140 lines

### Signatures

```text
// project.yml: entitlements com.apple.developer.weatherkit; bundleIdPrefix set to the owner's; deploymentTarget 18.0
// AttributionView is built in calculator-ui Slice 4; this slice adds the entitlement, the live provider wiring in AppEnvironment.live, and the link URL
public struct PrivacyPolicyLink: View { public init(url: URL) }
// docs/reviews/citations.md: the S13 report — every [VERIFY] and addendum-flagged citation with resolved / corrected / unresolved
// Promises (S8 owner, S9 owner, S13 owner): recorded by the owner on a device; Tunables.forecastHorizonDays updated to the observed horizon if it differs
```

### Internals

```text
AppEnvironment.live: swap NoAdsProvider for AdMobBannerProvider(adUnitID); PrivacyPolicyLink(url: the owner's page) wired into Settings › About; AttributionView (M3) gets the Apple asset and the legal link URL here
```

## Slice 3 — Accessibility, copy pass, TestFlight, listing

- **Delivers:** Dynamic Type at every size, VoiceOver labels on every figure, warning, estimate badge and timer state; the edge-case copy reviewed line by line against the outcomes actually produced by the fixtures; a TestFlight build; the App Store listing with the medical disclaimer in the description and privacy labels matching AdMob's non-personalised use.
- **Files:** `Sources/IcarusUI/Accessibility/Labels.swift`, `docs/APP_COPY.md`, `docs/release/app-store-listing.md`, `docs/release/privacy-labels.md`, `Tests/IcarusUITests/AccessibilityTests.swift`
- **Estimate:** ~260 lines

### Signatures

```text
public enum Labels { public static func figure(_ f: Figure, copy: AppCopy.Type) -> String }   // "Best time: 18 minutes. Estimate; depends on the up-and-about fraction assumption."
// docs/release/*.md: owner-facing checklists; not rendered in the app
// Promises (S9 owner): every FigureView, Warning row, notice, and TimerPhase has a non-empty accessibilityLabel from AppCopy; AccessibilityTests asserts the labels exist for a fixture result
```

### Internals

```text
AccessibilityTests: render ResultView for use case fixtures in a hosting controller, walk the accessibility tree, assert labels present and non-literal (resolved via AppCopy)
docs/release/app-store-listing.md: description with the disclaimer paragraph, keywords, screenshots list, age rating; privacy-labels.md: data types AdMob collects in NPA mode, "Data not linked to you"
```
