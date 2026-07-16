# iOS In-App Purchases — Next Steps

Status as of 2026-07-15. Picks up where PRD #401 / issues #402–#406 left off,
and now also PRD #407 / issues #408–#409 (rebuilding the plugin against the
correct Godot point release).

## Where things stand

- **#402 (iOS export & on-device build)**: done. `export_presets.cfg` has an iOS
  preset (bundle ID `com.wizardkittenz.game`, iPhone-only, team `T6DGD6WGY8`).
  A build has already been through TestFlight.
- **#403 (BillingManager two-backend facade)**: done, and just corrected. The
  original `AppleStoreKitBackend` (commit `2b312e6`) assumed a signal-based
  plugin API that doesn't exist. Commit `7eac420` rewrote it against the real
  plugin source from `godot-sdk-integrations/godot-ios-plugins` — see the
  header comment in `scripts/core/apple_storekit_backend.gd` for the verified
  API shape. All GUT tests pass (2815/2815).
- **#404 (device-ID fallback)**: done.
- **Steps 1 and 2 below are done.** The InAppStore plugin is built and wired
  into `export_presets.cfg`; a headless `--export-debug "iOS"` confirms
  `inappstore.xcframework` is linked into the generated Xcode project and all
  2812 GUT tests still pass. What's left is entirely manual: App Store
  Connect setup (#405) and on-device QA (#406).
- **#407/#408 (Godot version pin for the plugin)**: done. The originally
  committed plugin was built against the `godot` submodule's `4.6-stable`
  tag, which actually resolves to the 4.6.0 release — a mismatch against the
  installed editor/export templates (`4.6.2.stable.official.71f334935`) that
  broke the Xcode archive link step with undefined `ClassDB`/`MethodBind`
  symbols. The plugin has been rebuilt against the `4.6.2-stable` tag
  specifically, in `release` config (not `release_debug`), matching the
  installed editor/templates exactly. See the **Godot version pin** note
  below — this must be redone any time the editor/export template version
  changes.

## Step 1 — Build the InAppStore plugin

No prebuilt binaries are published for Godot 4.x (checked the releases page:
only Godot 3.x header/plugin bundles exist). It has to be built locally
against a matching Godot checkout. This project is on **Godot 4.6**
(`config/features` in `project.godot`).

### Godot version pin — read this before rebuilding

The `godot` submodule tag used to build the plugin **must match the
installed Godot editor and export templates exactly**, down to the point
release. Currently that's **`4.6.2-stable`**, matching the installed editor
`4.6.2.stable.official.71f334935` and the export templates at
`~/Library/Application Support/Godot/export_templates/4.6.2.stable`.

Do **not** use the `4.6-stable` tag — despite the name, it resolves to the
**4.6.0** release, not the latest 4.6.x point release. Building against it
while running a newer 4.6.x editor is exactly what broke the Xcode archive
previously (see PRD #407 / issue #408): the link step failed with undefined
`ClassDB`/`MethodBind` symbols.

The reason this matters: Godot's iOS plugins are statically linked directly
against the engine's internal `ClassDB`/`MethodBind` ABI, which is **not**
guaranteed stable across point releases — unlike GDExtension's stable ABI,
which is designed to tolerate this. A plugin built against 4.6.0 can
reference symbols that don't exist, or don't match, in a 4.6.2 engine core,
and that mismatch is invisible until Xcode's link step (a headless
`--export-debug` will not catch it). **Any time the installed Godot
editor/export template version changes, the plugin must be rebuilt from a
submodule checkout of the matching tag** — this is not a one-time fix.

```bash
git clone https://github.com/godot-sdk-integrations/godot-ios-plugins.git
cd godot-ios-plugins

# Get a matching Godot checkout for headers. Either clone the submodule:
git submodule update --init godot
cd godot && git checkout 4.6.2-stable && cd ..   # must match installed editor/templates exactly

# Build Godot for iOS (this is the slow part — expect 30-60+ min):
brew install scons   # if not already installed
cd godot
scons platform=ios target=editor
cd ..

# Build the InAppStore plugin as an xcframework (release, not release_debug,
# for anything headed to actual App Store submission):
./scripts/generate_xcframework.sh inappstore release 4.0
```

Output lands in `godot-ios-plugins/bin/` as `inappstore.release.xcframework`
(and matching `.a` files if you need those instead).

If `scons platform=ios target=editor` fails on a version mismatch, check
`plugins/inappstore/` in the repo for any per-version notes, and confirm the
`godot` submodule is checked out at the tag matching your installed
editor/templates (not `master`, and not the bare `X.Y-stable` branch tag,
which points at `X.Y.0`).

## Step 2 — Install the plugin into the project (done)

The `godot-ios-plugins` README says `res://ios/plugin/`, but that's wrong for
Godot 4.6 — `EditorExportPlatformIOS::get_plugins()` scans
`res://<platform_name>/plugins`, i.e. **`res://ios/plugins/`** (plural). Using
the singular directory silently produces an export with no plugin linked (no
error — the exporter just finds zero `.gdip` files).

1. `res://ios/plugins/` now contains `inappstore.gdip` (from
   `godot-ios-plugins/plugins/inappstore/inappstore.gdip`, unmodified) and
   `inappstore.xcframework` (built via `generate_xcframework.sh`, then
   renamed from `inappstore.release_debug.xcframework` to
   `inappstore.xcframework` to match the `binary=` field in the `.gdip`).
2. `export_presets.cfg` has `plugins/InAppStore=true` appended to the iOS
   preset's options (mirroring `plugins/GodotGooglePlayBilling=true` for
   Android).
3. Verified with a headless export:
   `Godot --headless --export-debug "iOS" ./wizard-kittenz.xcodeproj` —
   `project.pbxproj` now references `inappstore.xcframework` at
   `wizard-kittenz/dylibs/ios/plugins/inappstore.xcframework`. `Engine.has_
   singleton("InAppStore")` should be true on-device (it's never true in the
   editor/GUT — iOS plugin singletons only exist in exported builds).
4. The plugin binaries were built locally (not committed anywhere outside
   this repo) from `godot-sdk-integrations/godot-ios-plugins`, at Godot
   `4.6.2-stable`, using `release` config — see the **Godot version pin**
   note in Step 1. The working tree is at `~/IdeaProjects/godot-ios-plugins`
   with the `godot` submodule checked out to `4.6.2-stable`. If the installed
   editor/export templates are ever upgraded past 4.6.2, this must be redone
   against the new matching tag.

## Step 3 — App Store Connect setup (issue #405, all manual)

- Create the app record for `com.wizardkittenz.game`.
- Add 4 **Consumable** IAP products, product IDs matching `PurchaseRegistry`
  exactly: `gem_bundle_starter`, `gem_bundle_explorer`,
  `gem_bundle_adventurer`, `gem_bundle_hero`.
- Price them to match `ShopCatalog`'s existing Android price points ($0.99 /
  $4.99 / $9.99 / $19.99).
- Create a sandbox Apple ID tester account for purchase QA.
- Confirm/expand the internal TestFlight group.

## Step 4 — On-device QA (issue #406)

Once the plugin is wired in and products exist in App Store Connect, walk the
full checklist in #406 — in particular the purchase-specific items:

- Purchase each of the 4 Gem Bundle products with the sandbox account; confirm
  Gems are credited via `CurrencyLedger`.
- Repurchase the same bundle again; confirm it credits again (these are
  Consumable, not one-time).
- Confirm a Gems/Gold-only purchase (class upgrade, cosmetic) still works
  unmodified — regression check on the billing facade refactor.
- Force-quit/relaunch; confirm identity/save persistence still holds.

## Notes for whoever picks this up

- `scripts/core/apple_storekit_backend.gd` has no signals to react to from
  the plugin — it polls `get_pending_event_count()` /
  `pop_pending_event()` on a 0.25s `Timer` owned by `BillingManager`. If a
  purchase seems to hang on-device, check `poll()` is actually being called
  (i.e. `BillingManager._poll_timer` exists) before suspecting the plugin.
- Gem Bundles are Consumable on both stores — `finish_transaction()` is
  called by our code after we've handled a purchase/restore event, not left
  to the plugin's `auto_finish_transaction` (deliberately left `false`).
- `.gitignore` now correctly excludes the generated iOS export output
  (`wizard-kittenz.xcodeproj/`, `wizard-kittenz.xcframework/`,
  `wizard-kittenz.pck`, `MoltenVK.xcframework/`, `PrivacyInfo.xcprivacy`,
  `wizard-kittenz/`) — these regenerate on every export and shouldn't be
  committed. Don't `git add -A` a fresh export without checking `git status`
  first in case new generated paths show up.
- The committed `inappstore.xcframework` is now built with `release` config
  against Godot `4.6.2-stable` (see the **Godot version pin** note in Step
  1) — appropriate for actual App Store submission, not just TestFlight/
  sandbox QA. `release_debug` binaries can behave differently under App
  Review, so don't swap back to a `release_debug` build for a real
  submission.
- The plugin's iOS ABI is not stable across Godot point releases (see Step
  1). If the installed editor or export templates are upgraded, rebuild the
  plugin from a submodule checkout of the new matching tag before trusting
  the archive to link — a version mismatch here is invisible until Xcode's
  `Product > Archive` link step, not at export or GUT-test time.
- Headless export from the CLI works and is a fast way to sanity-check the
  plugin wiring without opening the editor: `Godot --headless --export-debug
  "iOS" ./wizard-kittenz.xcodeproj` (the app icon `ERROR: Can't open file`
  lines in that output are a pre-existing, unrelated gap — no icon files are
  configured in `export_presets.cfg`'s `icons/ios_*` fields — not something
  this work introduced).
