# Play Console Upload Errors — Resolution Plan

## Status

- [ ] Error 1 (PBL version) — needs manual Gradle wire-in (see below)
- [ ] Error 2 (64-bit) — needs Gradle cache clean (see below)
- [ ] Re-export, re-sign, re-upload after both fixes
[wizard-kittenz.aab](../wizard-kittenz.aab)
---

## Error 1: Play Billing Library too old / doesn't support Android 14

**Root cause:** The new `GodotGooglePlayBilling` 3.2.0 plugin uses Godot's `EditorExportPlugin`
mechanism to inject its AAR and Maven dependency (`billing-ktx:8.3.0`) into the Gradle build at
export time. That mechanism only fires when the addon is enabled in the Godot editor. The old
`plugins/GodotGooglePlayBilling=true` line in `export_presets.cfg` is the legacy `.gdap` format —
with those files deleted, nothing is being passed to Gradle, so no billing library is included.

**Fix A — Manually wire the new plugin into the Gradle build (immediate unblock)**

Step 1: Copy the new AARs into the Gradle build libs directory:

```
cp addons/GodotGooglePlayBilling/bin/release/GodotGooglePlayBilling-release.aar \
   android/build/libs/release/

cp addons/GodotGooglePlayBilling/bin/debug/GodotGooglePlayBilling-debug.aar \
   android/build/libs/debug/
```

Step 2: Add the Maven dependency to `android/build/build.gradle` in the `dependencies { }` block
(after the existing `implementation "androidx.documentfile..."` line):

```groovy
implementation "com.android.billingclient:billing-ktx:8.3.0"
```

**Fix B — Enable the addon in the Godot editor (long-term)**

Open Godot → Project → Project Settings → Plugins → enable "GodotGooglePlayBilling".

This ensures the EditorExportPlugin fires on future exports and handles the injection
automatically. Note: if Godot regenerates the Gradle template, Fix A's manual line will be
lost — Fix B prevents that.

---

## Error 2: Only 32-bit native code present

**Root cause:** The Gradle build cache contains stale intermediates from a previous build that
included the old 1.0.1 AAR (32-bit only). The Godot engine template AAR at
`android/build/libs/release/godot-lib.template_release.aar` already contains arm64-v8a native
libs, so this will resolve with a clean Gradle build.

**Fix: Delete stale Gradle outputs before re-exporting**

```
rm -rf android/build/.gradle
rm -rf android/build/build
```

Verify `export_presets.cfg` has `architectures/arm64-v8a=true` (currently set correctly).

---

## Error 3: Version code already used (v2 and v3 were rejected)

Resolved — version code is now 4. Before re-exporting, set it to 4 in the Godot editor:
Project → Export → Android → Version Code = 4. This prevents the editor from resetting it.

---

## Error 4: Version code 2 shadowed

Expected — the old AAB is automatically suppressed by the newer version code.

---

## Full Re-export Checklist

- [ ] Apply Error 1 Fix A (copy AARs to libs/, add billing-ktx dependency to build.gradle)
- [ ] Apply Error 1 Fix B (enable addon in Godot editor Project Settings → Plugins)
- [ ] Delete stale Gradle cache (`rm -rf android/build/.gradle android/build/build`)
- [ ] In Godot editor: set Export → Android → Version Code = 4
- [ ] Export release AAB from Godot editor
- [ ] Sign the AAB (jarsigner / apksigner)
- [ ] Upload to Play Console Internal Testing → Edit release → swap in the new AAB
- [ ] Confirm Play Console shows no PBL or 64-bit errors

---

## Notes

- `android/build/build.gradle` is part of Godot's Gradle build template. If Godot regenerates
  the template (Project → Install Android Build Template), the manual `billing-ktx` line will
  be overwritten. Enabling the addon via Fix B is the permanent solution.
- The `plugins/GodotGooglePlayBilling=true` line in `export_presets.cfg` is harmless but
  unused — it references the old `.gdap` format which no longer exists.
