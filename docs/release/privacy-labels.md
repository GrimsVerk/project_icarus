# App Store privacy: what to declare

A draft for the owner to check before submitting (R41, S16). It records what
the code does; the answers in App Store Connect are the owner's.

## What the app's own code sends off the device

- **The forecast request.** The coordinate goes to Apple's WeatherKit and
  nowhere else. No account, no identifier, no analytics. Open question for the
  owner: whether a request to an Apple service counts as "collected" for the
  label. If it does: Location › Precise location, App Functionality, not linked
  to the user, not used for tracking.
- **Nothing else.** The profile, the session history, the skin reports and the
  calibration stay on the device (SwiftData, `UserDefaults`, Application
  Support). Export writes a file only when the user asks.

## What the ad SDK sends

The Google Mobile Ads SDK, non-personalised (`npa=1` on every request), no App
Tracking Transparency prompt, so no IDFA. Google lists what the SDK collects in
its data disclosure guide; copy the current list from there rather than from
here: <https://developers.google.com/admob/ios/privacy/data-disclosure>.
At the time of writing that guide lists, for third-party advertising and
analytics: coarse location (from the IP address), device ID, product
interaction, advertising data, and crash, performance and other diagnostic data.

## Privacy manifest

`App/PrivacyInfo.xcprivacy`: no tracking, no tracking domains, no collected data
types of the app's own; one required-reason API, `UserDefaults` (CA92.1). The
Google SDKs ship their own manifests, and Xcode's privacy report (Archive ›
Generate Privacy Report) merges them; check that report against the labels
before submitting.

## The privacy policy

The page at `PRIVACY_POLICY_URL` (`project.yml`) has to say what the ad SDK
receives (R41). Settings links to it.
