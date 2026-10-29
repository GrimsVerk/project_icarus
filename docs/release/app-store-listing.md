# App Store listing: what the submission needs

A checklist, not copy. Every line a user reads, here or in the app, is the
owner's (S17); nothing below drafts any of it.

## In the project (`project.yml`)

- [ ] Bundle id: `options.bundleIdPrefix` is `com.example`.
- [ ] Signing: a `DEVELOPMENT_TEAM`, and the WeatherKit capability on the App ID
      (the entitlement is in `project.yml`; it needs the team to sign).
- [ ] `ADMOB_APP_ID` and `ADMOB_BANNER_UNIT_ID`: Google's test ids until the
      owner's AdMob app and banner unit exist.
- [ ] `PRIVACY_POLICY_URL`: an example.com placeholder.
- [ ] App icon: the project has no asset catalog yet; the store needs a
      1024×1024 icon.
- [ ] The location permission's purpose string
      (`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`): the system dialog
      shows it, so it is copy and needs an approved line. Without it iOS never
      asks, and the forecast falls back to manual entry.
- [ ] `MARKETING_VERSION` 1.0, `CURRENT_PROJECT_VERSION` 1: raise the build
      number for every upload.

## In App Store Connect

- [ ] Name, subtitle, description (with the medical disclaimer, R29), keywords,
      promotional text: the owner's copy.
- [ ] Category and age rating.
- [ ] Support URL and privacy policy URL.
- [ ] Privacy labels: `docs/release/privacy-labels.md`.
- [ ] Screenshots: the store needs the 6.9" size (1320×2868, e.g. iPhone 16 Pro
      Max). The screenshot walk (`.github/workflows/screenshots.yml`) uses
      iPhone 16; run it on a 6.9" simulator for store images.
- [ ] Export compliance: `ITSAppUsesNonExemptEncryption` is false (HTTPS only).
- [ ] TestFlight testers.

## On a device (owner criteria)

- [ ] S8 (live): the WeatherKit forecast matches the Weather app for the same hour.
- [ ] S9: Dynamic Type and VoiceOver; the VoiceOver labels need copy.
- [ ] S12, S13: per DESIGN §13.
- [ ] S16: a banner loads on the Calculator and the Learn list only; the consent
      form appears once in a region that requires it; the privacy link opens.
