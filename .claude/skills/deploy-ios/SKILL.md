---
name: deploy-ios
description: Bump the iOS build number, re-export the Xcode project from Godot, and walk through archiving and distributing wizard-kittenz to App Store Connect/TestFlight. Use when the user wants to deploy, ship, or upload a new iOS build, mentions TestFlight, App Store Connect, Xcode archive, or asks to increment/bump the iOS build number.
---

# Deploy iOS

Godot regenerates `wizard-kittenz.xcodeproj` from scratch on every export —
it is gitignored, disposable, and **wipes any manual Xcode signing tweaks**
every time. This skill exists because that regeneration silently
reintroduces a signing conflict that isn't obvious until Xcode's Archive
step fails.

## Steps

### 1. Bump the build number

Apple rejects a re-upload with the same normalized build number (`1` and
`1.0.0` are treated as identical). In `export_presets.cfg`, increment:

```
application/version="N"   # bump this — the build number
```

Leave `application/short_version` (marketing version, e.g. `"1.0"`) alone
unless the user asked for a version bump too.

### 2. Re-export from Godot

```bash
cd ~/IdeaProjects/wizard-kittenz
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --export-release "iOS" ./wizard-kittenz.xcodeproj
```

Use `--export-release`, not `--export-debug` — a debug export links the
debug-variant `libgodot.a` into `wizard-kittenz.xcframework`, which has a
different `ClassDB::bind_methodfi` ABI signature than the release engine.
If any native plugin (e.g. `inappstore.xcframework`) was built in `release`
config, an Xcode Archive (which builds Release) will fail to link with an
`Undefined symbol: ClassDB::bind_methodfi` error against a debug-exported
project.

Confirm the version landed:

```bash
grep -n "CURRENT_PROJECT_VERSION\|MARKETING_VERSION" wizard-kittenz.xcodeproj/project.pbxproj
```

### 3. Reapply the code-signing fix (every time)

The Godot iOS export template always writes the Release target config with
`CODE_SIGN_STYLE = "Automatic"` **and** a hardcoded
`CODE_SIGN_IDENTITY = "Apple Distribution"`. Xcode treats an explicit
identity alongside Automatic signing as a conflict and blocks Archive with:

> conflicting provisioning settings... Set the code signing identity value
> to "Apple Development"...

Fix it in `wizard-kittenz.xcodeproj/project.pbxproj` — find the **Release**
`XCBuildConfiguration` block for the app target (the one with
`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;`, not the earlier
project-level Release block) and change:

```
CODE_SIGN_IDENTITY = "Apple Distribution";
```
to
```
CODE_SIGN_IDENTITY = "Apple Development";
```

Automatic signing still resolves the correct distribution certificate at
archive/export time — this string is just what unblocks the conflict
check. There are two `CODE_SIGN_IDENTITY = "Apple Distribution"` lines in
the file; only change the one inside the target-level Release config block
(near `PRODUCT_BUNDLE_IDENTIFIER`), not the earlier project-level one.

### 4. Archive in Xcode (hand off to the user — this is HITL)

Tell the user to:

1. Open `wizard-kittenz.xcodeproj` in Xcode.
2. **Product > Clean Build Folder** (⇧⌘K) if this isn't a first-time archive —
   avoids stale link errors from a previous failed attempt.
3. Select **Any iOS Device (arm64)** as the run destination (not a simulator).
4. **Product > Archive**.
5. Watch for the undefined-symbol or signing errors above; if either
   appears, re-check steps 2–3 above were actually applied to the
   regenerated project file.

### 5. Distribute

In the Organizer window that opens after a successful archive:

1. Click **Distribute App**.
2. Choose **App Store Connect** — *not* "TestFlight Internal Only". The
   "TestFlight Internal Only" method skips App Store Connect entirely and
   can never be promoted to a full App Store submission later.
   "App Store Connect" is correct for both TestFlight testing and eventual
   App Store review — it's the same upload either way.
3. Use the recommended/automatic signing options through the wizard.
4. Click **Upload**.

### 6. Verify

- Build appears under **App Store Connect > Apps > (app) > TestFlight >
  Builds** within the usual processing window (minutes, sometimes longer).
- Confirm the build number shown matches what was bumped in step 1.
- If IAP/native plugins changed, see the on-device QA checklist pattern in
  `docs/ios-iap-next-steps.md` for what to verify post-install.

## Gotchas recap

| Symptom | Cause | Fix |
|---|---|---|
| `Undefined symbol: ClassDB::bind_methodfi(...)` | Exported with `--export-debug`, linking a debug engine lib against a release-built plugin | Re-export with `--export-release` |
| "conflicting provisioning settings... Apple Distribution... Automatic" | Godot's export template hardcodes `CODE_SIGN_IDENTITY` on the Release config every export | Reset it to `"Apple Development"` (step 3) |
| "Redundant Binary Upload... build number 'N'" | Build number unchanged since last upload | Bump `application/version` in `export_presets.cfg` and re-export |