# iOS In-App Purchases — Next Steps

Status as of 2026-07-15. Picks up where PRD #401 / issues #402–#406 left off.

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

## Step 1 — Build the InAppStore plugin

No prebuilt binaries are published for Godot 4.x (checked the releases page:
only Godot 3.x header/plugin bundles exist). It has to be built locally
against a matching Godot checkout. This project is on **Godot 4.6**
(`config/features` in `project.godot`).

```bash
git clone https://github.com/godot-sdk-integrations/godot-ios-plugins.git
cd godot-ios-plugins

# Get a matching Godot checkout for headers. Either clone the submodule:
git submodule update --init godot
cd godot && git checkout 4.6-stable && cd ..

# Build Godot for iOS (this is the slow part — expect 30-60+ min):
brew install scons   # if not already installed
cd godot
scons platform=ios target=editor
cd ..

# Build the InAppStore plugin as an xcframework:
./scripts/generate_xcframework.sh inappstore release_debug 4.0
```

Output lands in `godot-ios-plugins/bin/` as `inappstore.xcframework` (and
matching debug/release `.a` files if you need those instead).

If `scons platform=ios target=editor` fails on a version mismatch, check
`plugins/inappstore/` in the repo for any per-version notes, and confirm the
`godot` submodule is checked out at `4.6-stable` (not `master`).

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
   this repo) from `godot-sdk-integrations/godot-ios-plugins` at Godot
   `4.6-stable`, using `release_debug` config per the doc's original command.
   If you need to rebuild (e.g. for a `release` config before App Store
   submission), the working tree is at `~/IdeaProjects/godot-ios-plugins`
   with the `godot` submodule already checked out to `4.6-stable`.

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
- The committed `inappstore.xcframework` was built with `release_debug`
  (matching the doc's original Step 1 command). That's fine for TestFlight/
  sandbox QA (#406). Before a real App Store submission, rebuild with
  `./scripts/generate_xcframework.sh inappstore release 4.0` and swap it in —
  `release_debug` binaries can behave differently under App Review.
- Headless export from the CLI works and is a fast way to sanity-check the
  plugin wiring without opening the editor: `Godot --headless --export-debug
  "iOS" ./wizard-kittenz.xcodeproj` (the app icon `ERROR: Can't open file`
  lines in that output are a pre-existing, unrelated gap — no icon files are
  configured in `export_presets.cfg`'s `icons/ios_*` fields — not something
  this work introduced).
