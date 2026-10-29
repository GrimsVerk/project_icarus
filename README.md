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

On the Mac, by the agent:

```sh
cp Local.xcconfig.example Local.xcconfig   # gitignored; fill in both values
# The team id (ten characters). If this prints nothing, pick the Personal
# Team under Signing & Capabilities in Xcode and read it from there.
defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier | grep -E 'teamID|teamName|isFree'
xcodegen generate
xcodebuild -showdestinations -project ProjectIcarus.xcodeproj -scheme ProjectIcarus   # the iPhone's id
xcodebuild build -project ProjectIcarus.xcodeproj -scheme ProjectIcarus \
  -destination 'platform=iOS,id=<iPhone id>' -derivedDataPath DerivedData \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app --device <iPhone id> \
  DerivedData/Build/Products/Debug-iphoneos/ProjectIcarus.app
```

Or open `ProjectIcarus.xcodeproj`, choose the iPhone as the run destination and
press ⌘R. In `Local.xcconfig`, replace `CHANGEME` in the bundle id with
something of your own: a Personal Team must register an id nobody else has.

- The free profile expires after 7 days; the app then won't open. Build and
  install again; the app's data stays.
- No UV forecast until the paid program: a Personal Team can't have WeatherKit,
  so `Local.xcconfig` drops its entitlement and the Calculator shows its
  no-forecast result. Learn, History and Settings work. Delete the
  `CODE_SIGN_ENTITLEMENTS =` line once the paid team's App ID has WeatherKit.
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
