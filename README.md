# project_icarus

A free iOS app that plans sun exposure for a durable tan while staying under
your burn line: a Calculator tab and a Learn tab. Code name Icarus.
What and why: `docs/VISION.md`, `docs/DESIGN.md`. Agents: start with `AGENTS.md`.

Made from [grimsverk-template](https://github.com/GrimsVerk/grimsverk-template).

## Develop

```sh
brew install xcodegen swiftformat swiftlint pre-commit
xcodegen generate                # makes ProjectIcarus.xcodeproj from project.yml
open ProjectIcarus.xcodeproj
pre-commit install               # checks on every commit
```

The engine, content and data targets also build on Linux: `swift test`, then
`acceptance/S*.sh` for the scripted success criteria.

## Run on your iPhone

With a free Apple ID (a "Personal Team"), before the paid Developer Program.

Once, by the owner:

1. Xcode > Settings > Accounts > + > Apple ID: sign in. This makes the
   Personal Team.
2. Connect the iPhone by cable, unlock it and tap Trust This Computer.
3. On the iPhone: Settings > Privacy & Security > Developer Mode, on. It
   restarts; confirm. The switch appears once the phone has been connected to
   Xcode.
4. After the first install, before the app opens: Settings > General > VPN &
   Device Management > your Apple ID > Trust.

On the Mac, by the agent. The first run that worked (2026-10-29: iPhone 16,
iOS 26.5.2, Xcode 27.1, macOS 27.2) needed the keychain steps below and
passed the signing values on the `xcodebuild` line, not through
`Local.xcconfig`. Why it skipped `Local.xcconfig` is not recorded: CI only
checks that the file's values resolve, so the file has never signed a real
build. The command line below is the route known to work; `Local.xcconfig`
should resolve to the same settings but is untried on a device.

Once per Mac, if signing fails with `errSecInternalComponent`, "unable to
build chain", or `security find-identity -v -p codesigning` lists no valid
identity:

```sh
# Apple's WWDR G3 intermediate, which signs Apple Development certificates.
curl -fsSLO https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
security add-certificates -k ~/Library/Keychains/login.keychain-db AppleWWDRCAG3.cer
# Over SSH nobody can click "Allow" when codesign asks for the key: let it in.
# Asks for the Mac's login password.
security unlock-keychain ~/Library/Keychains/login.keychain-db
security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db
```

The team id is ten characters. Any of these: Xcode > Settings > Accounts; the
`OU=` field of the signing certificate; Xcode's own record.

```sh
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject   # OU=<team id>
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -E 'teamID|teamName|isFree'
```

The bundle id: keep the one already on the phone, `com.grimsverk.icarus.personaldev`.
A different id installs a second, empty copy of the app and uses up one of
the Personal Team's 10 new ids a week.

Build, install and look:

```sh
xcodegen generate
xcrun devicectl list devices                      # the iPhone's id
printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict/></plist>\n' \
  > "$TMPDIR/empty.entitlements"                  # signs without WeatherKit
xcodebuild build -project ProjectIcarus.xcodeproj -scheme ProjectIcarus \
  -destination 'platform=iOS,id=<iPhone id>' -derivedDataPath DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM=<team id> CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER=com.grimsverk.icarus.personaldev \
  CODE_SIGN_ENTITLEMENTS="$TMPDIR/empty.entitlements"
xcrun devicectl device install app --device <iPhone id> \
  DerivedData/Build/Products/Debug-iphoneos/ProjectIcarus.app
xcrun devicectl device capture screenshot --device <iPhone id>   # over the cable; --help for options
```

With `Local.xcconfig` instead: `cp Local.xcconfig.example Local.xcconfig`, put
the team id and the bundle id above in it, `xcodegen generate`, check what
Xcode resolves, then the same build without the four overrides:

```sh
.github/scripts/check-signing.sh com.grimsverk.icarus.personaldev "" <team id>
```

The file leaves `CODE_SIGN_ENTITLEMENTS` empty, where the working run pointed
it at an empty plist. If signing then complains about entitlements, set it to
an empty plist's path in `Local.xcconfig` as above and note it here.

Or open `ProjectIcarus.xcodeproj`, choose the iPhone as the run destination and
press ⌘R, with `Local.xcconfig` filled in.

- The free profile expires after 7 days; the app then won't open. Build and
  install again; the app's data stays.
- No UV forecast until the paid program: a Personal Team can't have WeatherKit,
  so the build signs without its entitlement (the empty plist, or
  `Local.xcconfig`) and the Calculator shows its no-forecast result. Learn,
  History and Settings work. Once the paid team's App ID has WeatherKit, drop
  the `CODE_SIGN_ENTITLEMENTS` override or its line in `Local.xcconfig`.
- A free account can have 3 apps of its own on a device at a time and register
  10 bundle ids a week.

## CI

`ci.yml` runs on every push to `main`: secret scan, format, lint, and the
Linux tests. `nightly.yml` builds and tests the app in Xcode on macOS.

## Set up GitHub (once)

`scripts/setup-github.sh --public` deletes merged branches and protects `main`
from force-pushes and deletion.

## Template updates

`scripts/update-from-template.sh` pulls in the latest template on a branch and opens a PR.

## License

[PolyForm Shield License 1.0.0](LICENSE): use, change and share this software
for any purpose except providing a product that competes with it. The
`Required Notice:` line at the top of `LICENSE` must travel with any copy.
Outside contributions need a contributor licence agreement first; none is set
up yet, so no outside code is merged.
