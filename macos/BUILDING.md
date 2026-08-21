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

## Quick repeatable build

After the prerequisites have been installed once, run the following commands
from the repository root whenever a new distributable package is needed:

```sh
# 1. Rebuild the shared library for both macOS architectures in release mode.
TOOLCHAINS=Metal \
  zig build -Doptimize=ReleaseFast -Demit-macos-app=false

# 2. Remove stale Xcode products, then build an ad-hoc-signed release app.
macos/build.nu --configuration ReleaseLocal --action clean
macos/build.nu --configuration ReleaseLocal

# 3. Create a commit-specific transfer archive.
REV=$(git rev-parse --short HEAD)
ZIP="macos/build/Ghostty-${REV}-macOS13-universal.zip"
ditto -c -k --sequesterRsrc --keepParent \
  macos/build/ReleaseLocal/Ghostty.app "$ZIP"

# 4. Check the archive and record its checksum.
unzip -t "$ZIP"
shasum -a 256 "$ZIP"
```

The application before compression is always available at:

```text
macos/build/ReleaseLocal/Ghostty.app
```

Do not omit the first step when shared Zig code under `src/` changed. Otherwise
Xcode can link an older or Debug `GhosttyKit`, causing missing changes or the
debug-build warning. The clean step prevents Xcode products from a previous
configuration or coverage-enabled test build from being reused.

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
TOOLCHAINS=Metal xcrun -sdk macosx metal --version
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
TOOLCHAINS=Metal xcrun -sdk macosx metal --version
TOOLCHAINS=Metal xcrun -sdk macosx --find metallib
```

If the component is installed but plain `xcrun metal` still reports it missing,
select the separate toolchain explicitly with `TOOLCHAINS=Metal` as shown
above. This stable name lets Xcode resolve the current MobileAsset version and
does not depend on a boot-specific mount path.

For diagnosis, `xcodebuild -showComponent MetalToolchain` prints the installed
component details. The following command shows the actual compiler selected by
Xcode:

```sh
TOOLCHAINS=Metal xcrun -sdk macosx --find metal
```

Do not commit a MobileAsset mount path from `/private/var/run/...` into the
build scripts. It is machine- and boot-specific.

## Build procedure

When shared Zig code has changed, first update the underlying Ghostty library.
Use `ReleaseFast` for a ReleaseLocal application; otherwise Xcode will link the
default Debug library and the application will display a debug-build warning:

```sh
TOOLCHAINS=Metal \
  zig build -Doptimize=ReleaseFast -Demit-macos-app=false
```

Xcode 26 distributes the Metal compiler as a separate toolchain. Selecting it
by the stable `Metal` identifier lets `xcrun` resolve the current installed
version without embedding a versioned MobileAsset mount path in the build.

Then build the application through the repository's macOS wrapper:

```sh
macos/build.nu --configuration ReleaseLocal --action clean
macos/build.nu --configuration ReleaseLocal
```

The wrapper explicitly disables Xcode code coverage for non-test actions.
Without this override, a scheme-level coverage setting can instrument even a
ReleaseLocal binary and cause the distributed application to create
`default.profraw` files at runtime.

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

# A distributable binary must not contain LLVM coverage instrumentation.
! nm -a "$APP/Contents/MacOS/ghostty" 2>/dev/null | grep -q __llvm_profile_runtime
! otool -l "$APP/Contents/MacOS/ghostty" | grep -q __llvm_prf_
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
