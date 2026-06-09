# MacBull 🐂

[![Release](https://github.com/jamiehook/MacBull/actions/workflows/release.yml/badge.svg)](https://github.com/jamiehook/MacBull/actions/workflows/release.yml)

A macOS menu-bar app that wraps the built-in `/usr/bin/caffeinate` command, so you
can toggle each sleep-prevention mode with a click instead of remembering flags.

The menu-bar icon is a bull: **snorting** while your Mac is being kept awake, and
**asleep** (with a "z") when normal sleep is allowed — so you can read its state at
a glance.

> **Note:** There are already plenty of `caffeinate` front-ends and keep-awake
> menu-bar apps out there — MacBull isn't trying to outdo any of them. It's a
> personal experiment, built for fun.

## Download

Grab the latest `.dmg` from the
[**Releases**](https://github.com/jamiehook/MacBull/releases/latest) page, open it,
and drag **MacBull** onto the Applications folder.

The app is ad-hoc signed (not notarized with an Apple Developer ID), so the first
time you launch it macOS Gatekeeper will block it. To open it once: **right-click
the app → Open** and confirm — or allow it under *System Settings → Privacy &
Security*. After that it launches normally. The download is a universal build, so
it runs natively on both Apple Silicon and Intel Macs.

## Menu

| Item | caffeinate flag | What it does |
|------|-----------------|--------------|
| Turn On / Off (⌘T) | — | Start/stop with the selected modes |
| Prevent display sleep | `-d` | Display won't sleep |
| Prevent idle sleep | `-i` | System won't idle-sleep |
| Prevent disk idle sleep | `-m` | Disk won't idle-sleep |
| Prevent system sleep on AC | `-s` | No system sleep while on power |
| Keep display awake | `-u` | Declares the user active / turns display on |
| Duration | `-t` | No limit, or 15 min – 8 hours |
| Launch at login | — | Auto-start at login (via `SMAppService`) |
| Quit MacBull (⌘Q) | — | Release everything and exit |

Tick any combination of modes, pick a duration, and hit **Turn On**. Changing a
mode while active restarts `caffeinate` with the new flags; turning every mode off
releases sleep entirely. Selections are remembered between launches.

The spawned `caffeinate` process is launched with `-w <app-pid>`, so it always
releases its power assertion and exits when the app does — even on a crash or
force-quit. Your Mac can't get stuck awake.

## Build it yourself

Don't want to use the release `.dmg`? Here's how to build and install MacBull
manually. Requires the Swift toolchain (Xcode or Command Line Tools), macOS 13+.

```sh
./build.sh           # builds build/MacBull.app
./build.sh install   # builds, copies to /Applications, and launches
```

To produce a distributable disk image like the one on the Releases page, run
`./package.sh` (outputs `build/MacBull-<version>.dmg`).

To start already caffeinated (handy with *Launch at login*), set
`MACBULL_AUTOSTART=1` in the environment.

## Releasing

Releases are built and published automatically by GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)) — there is no
manual upload step. To cut a release, tag a version and push the tag:

```sh
git tag v1.2.0
git push origin v1.2.0
```

On a `v*` tag push, CI runs on a full-Xcode macOS runner, stamps the version into
`Info.plist` from the tag, builds a **universal** (Apple Silicon + Intel) `.dmg`,
and publishes a GitHub release with it attached. (Running the workflow manually
from the Actions tab builds the same DMG but only uploads it as an artifact, for
testing — it doesn't publish a release.)

Conventions:

- **User-facing changes get a version bump** (roughly [SemVer](https://semver.org)):
  a new capability bumps the minor version — e.g. adding Intel support was
  `1.0.0` → `1.1.0` — and fixes bump the patch version.
- **Never mutate an already-published release.** Its bytes shouldn't change after
  people may have downloaded them; ship a new version instead.
- The **git tag is the source of truth** for the version, so you don't have to edit
  `Info.plist` by hand (keeping it in sync is fine, but CI overwrites it from the tag).

## The icons

All artwork is generated from code — no binary assets to hand-edit.

```sh
./Icon/make.sh             # renders the app icon → Icon/AppIcon.icns
./Icon/make_menubar.swift  # renders the menu-bar bull glyphs (awake / asleep)
```

The menu-bar glyph has two states — a snorting bull when keeping the Mac awake,
and a sleeping bull (with a "z") when sleep is allowed. Edit `Icon/make_icon.swift`
or `Icon/make_menubar.swift` (small Core Graphics programs) to change the artwork.

## Project layout

```
Package.swift                 SwiftPM manifest (executable target)
Info.plist                    Bundle metadata (LSUIElement = menu-bar-only app)
build.sh                      Compiles and assembles the .app bundle
package.sh                    Builds the distributable .dmg + ReleaseInfo.json
Icon/
  make_icon.swift              Core Graphics renderer for the app icon
  make.sh                      Renders + packs AppIcon.icns
  AppIcon.icns                 Generated app icon
  make_menubar.swift           Renderer for the two menu-bar bull glyphs
  menubar-awake.pdf            Menu-bar glyph: snorting bull (awake)
  menubar-asleep.pdf           Menu-bar glyph: sleeping bull (asleep)
Sources/MacBull/
  MacBullApp.swift             @main App + MenuBarExtra
  MenuContent.swift            The dropdown menu UI
  CaffeinateController.swift   Owns the caffeinate subprocess and state
```

## License

[MIT](LICENSE) © Jamie Hook
