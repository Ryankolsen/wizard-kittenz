---
name: deploy-android
description: Bump the Android version code, export the .aab from Godot, and walk through uploading wizard-kittenz to Google Play Console (closed/internal testing or production). Use when the user wants to deploy, ship, or upload a new Android build, mentions Google Play Console, an .aab, or asks to increment/bump the Android version code.
---

# Deploy Android

## Steps

### 1. Bump the version code

Google Play rejects a re-upload with a version code it's already seen —
this holds even if the last release was iOS-only and no Android-relevant
code changed. Check the highest version code already live for *any* track
(production, closed testing, internal testing) in Play Console under
**Test and release** before assuming the value in the repo is next-in-line;
it may have already been bumped and uploaded outside this checkout.

In `export_presets.cfg`, under `[preset.0.options]` (the `Android` preset):

```
version/code=N   # bump this — the version code
```

Leave `version/name` (marketing version, e.g. `"1.0"`) alone unless the
user asked for a version bump too.

### 2. Export the .aab from Godot

```bash
cd ~/IdeaProjects/wizard-kittenz
/Users/ryankolsen/Downloads/Godot.app/Contents/MacOS/Godot \
  --headless --export-release "Android" ./wizard-kittenz.aab
```

Confirm the file landed:

```bash
ls -la wizard-kittenz.aab
```

Uses `gradle_build/use_gradle_build=true`, so this invokes a Gradle build
under the hood — expect it to take longer than a quick headless export.
Watch the tail of the output for `[ DONE ] export`; a Gradle failure will
show up as a non-zero exit / error text instead.

### 3. Upload to Play Console

1. Go to **Play Console > Test and release** for the app.
2. Pick the track: **Closed testing** (the "wizard kittens test 1" track
   has historically been used for pre-release validation), **Internal
   testing**, or **Production**, depending on what the user asked for. If
   unclear, ask — don't assume production.
3. Create a new release, upload `wizard-kittenz.aab`.
4. Confirm the version code shown in the release matches what was bumped
   in step 1.
5. Roll out.

### 4. Verify

- Build appears in the track's release list with the correct version code
  and processes without errors.
- Install via the track's testing link (Play Store, not sideloaded) on a
  test device.
- If IAP changed on the Android side specifically, confirm a purchase:
  Google Play Billing purchases on a closed/internal testing track with the
  tester's account added as a license tester show a **test-order** flow —
  no real charge. Confirm Gems credit via `CurrencyLedger`, and that
  repurchasing the same Consumable bundle credits again.

## Notes

- Android in-app purchases go through `GodotGooglePlayBilling`
  (`addons/GodotGooglePlayBilling/`), a completely separate plugin from
  iOS's `InAppStore` (`ios/plugins/inappstore.xcframework`). Work on one
  platform's billing plugin does not require touching or rebuilding the
  other — `BillingManager` (`scripts/core/billing_manager.gd`) auto-detects
  whichever platform singleton is present at runtime and dispatches
  accordingly. See the `deploy-ios` skill for the iOS-side equivalent of
  this workflow.
- Unlike iOS, there's no gitignored/regenerated project file to fight with
  here — the `.aab` is a direct build artifact, not an intermediate project
  that needs manual post-export fixes.