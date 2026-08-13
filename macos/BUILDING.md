# Building Ghostty for macOS

This note records the practical steps and common failure modes for producing a
local macOS application bundle from this repository. The project-specific agent
instructions in `macos/AGENTS.md` remain authoritative.

## Intended output

The normal local release build produces:

```text
macos/build/ReleaseLocal/Ghostty.app
```

The project currently sets the main application deployment target to macOS
13.0. The Xcode project builds a universal binary containing both `arm64` and
`x86_64`, unless the architectures are explicitly overridden.

`ReleaseLocal` is suitable for local testing and direct transfer when the
recipient is prepared to approve an unnotarized application. It uses an ad-hoc
"Sign to Run Locally" signature. It is not equivalent to a Developer ID signed
and Apple-notarized public release.

## Prerequisites

- Full Xcode, not only Command Line Tools
- Zig at the version expected by the repository
- Nushell (`nu`) for `macos/build.nu`
- GNU gettext (`msgfmt`) for localized resources
- Xcode's separately downloadable Metal Toolchain

With Homebrew, the non-Xcode tools can be installed with:

```sh
brew install zig nushell gettext
```

Verify the environment before building:

```sh
xcode-select -p
xcodebuild -version
nu --version
msgfmt --version
xcrun --find metal
```

`xcode-select -p` should point inside the full application, normally:

```text
/Applications/Xcode.app/Contents/Developer
```

If it still points at `/Library/Developer/CommandLineTools`, initialize Xcode:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

## Xcode 26 and the Metal Toolchain

Xcode 26 may install the `xcrun metal` launcher without installing the actual
Metal compiler. The resulting error is misleading because `xcrun --find metal`
can still return a path:

```text
cannot execute tool 'metal' due to missing Metal Toolchain
```

Install the component with:

```sh
xcodebuild -downloadComponent MetalToolchain
xcodebuild -showComponent MetalToolchain
```

The second command should report `Status: installed`. Then run:

```sh
sudo xcodebuild -runFirstLaunch
xcrun metal --version
```

If the component is installed but `xcrun metal` still reports it missing, Xcode
has probably failed to persist its toolchain mapping under
`~/Library/Developer/Xcode`. Open Xcode once, allow it to install components,
and retry outside any filesystem sandbox. A reboot may also be required after a
MobileAsset Metal Toolchain is mounted.

For diagnosis, `xcodebuild -showComponent MetalToolchain` prints the toolchain
identifier and search path. A command such as the following confirms whether
the downloaded compiler itself is usable:

```sh
xcrun --toolchain <toolchain-identifier> --find metal
```

Do not commit a MobileAsset mount path from `/private/var/run/...` into the
build scripts. It is machine- and boot-specific.

## Build procedure

When shared Zig code has changed, first update the underlying Ghostty library.
Use `ReleaseFast` for a ReleaseLocal application; otherwise Xcode will link the
default Debug library and the application will display a debug-build warning:

```sh
zig build -Doptimize=ReleaseFast -Demit-macos-app=false
```

Then build the application through the repository's macOS wrapper:

```sh
macos/build.nu --configuration ReleaseLocal
```

Do not use `zig build` as the final macOS application build. The wrapper invokes
the Xcode project with a clean environment and places products in the expected
directory.

The first Xcode build resolves the Sparkle Swift package and may appear quiet
while cloning it. Its cache is normally under:

```text
~/Library/Caches/org.swift.swiftpm
```

## Cache and sandbox failures

Zig, Clang/Metal, and Xcode write outside the repository by default. Restricted
automation environments may fail even though the host is correctly configured.
Typical errors include:

```text
unable to open global cache directory '~/.cache/zig'
unable to open output file '~/.cache/clang/ModuleCache/...'
permission to save ... XcodeToMetalToolchainIndexMapping.plist
```

For Zig-only cache failures, redirect the global cache to a writable location:

```sh
ZIG_GLOBAL_CACHE_DIR=/tmp/ghostty-zig-global-cache \
  zig build -Demit-macos-app=false
```

Metal module-cache failures can be avoided with an explicit compiler module
cache argument when diagnosing a custom build step. Xcode application builds,
component registration, SwiftPM resolution, and signing should instead be run
with normal access to `~/Library/Developer`, `~/Library/Caches`, and Xcode's
system services.

## Validate macOS 13 compatibility

Do not rely only on the Xcode project setting. Check the completed bundle:

```sh
APP=macos/build/ReleaseLocal/Ghostty.app

plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist"
lipo -archs "$APP/Contents/MacOS/ghostty"
vtool -show-build "$APP/Contents/MacOS/ghostty"
codesign --verify --deep --strict --verbose=2 "$APP"
```

Expected key results are:

```text
LSMinimumSystemVersion: 13.0
architectures: x86_64 arm64
LC_BUILD_VERSION minos: 13.0 for both slices
codesign: valid on disk
```

Also inspect executable nested plug-ins and frameworks. A nested executable
with a deployment target newer than 13.0 can make a feature or the whole bundle
unusable on macOS 13 even when the main executable is correct.

## Create a transfer ZIP

Use `ditto`, rather than a generic ZIP tool, to preserve the macOS bundle
structure, resource forks, and extended attributes:

```sh
cd macos/build/ReleaseLocal
ditto -c -k --sequesterRsrc --keepParent \
  Ghostty.app ../Ghostty-macOS13-universal-ReleaseLocal.zip
```

Verify the archive and record a checksum:

```sh
unzip -t macos/build/Ghostty-macOS13-universal-ReleaseLocal.zip
shasum -a 256 macos/build/Ghostty-macOS13-universal-ReleaseLocal.zip
```

## Distribution caveat

An ad-hoc-signed `ReleaseLocal` bundle can run on macOS 13, but Gatekeeper may
block it after transfer because it is not notarized. The recipient may need to
right-click the application and choose **Open**, then approve it in Privacy &
Security.

A frictionless public distribution requires all of the following:

1. Membership in the Apple Developer Program.
2. A Developer ID Application certificate.
3. Signing the application and every nested executable with that identity.
4. Submitting the final ZIP or disk image to Apple's notary service.
5. Stapling the notarization ticket and validating it with `spctl`.

Compatibility with macOS 13 and Gatekeeper acceptance are separate concerns:
the deployment target controls the former, while Developer ID signing and
notarization control the latter.
