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
