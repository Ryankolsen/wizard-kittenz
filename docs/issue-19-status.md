# Issue #19 — Google Play IAP Setup: Status

## Done
- Created the app in Google Play Console (`com.wizardkittenz.game`)
- Downloaded `GodotGooglePlayBilling.1.0.1.release.aar` + `.gdap` → placed in `android/plugins/`
- Built `BillingManager` autoload (`scripts/billing_manager.gd`) — wraps the plugin, degrades gracefully on desktop/test builds
- Registered `BillingManager` in `project.godot`

## Still To Do

### Play Console (web)
- [ ] Define consumable product `revive_token_pack_5` and set it to **Active**
- [ ] Set content rating (shelved — revisiting all-ages vs 17+ separately)

### Godot Editor
- [ ] Create Android export preset: **Project → Export → Add... → Android**, package name `com.wizardkittenz.game`
- [ ] In the preset, enable plugin: **Plugins → GodotGooglePlayBilling ✓**

### Device Verification
- [ ] Export a debug APK and run on a physical Android device
- [ ] Confirm output log shows: `BillingManager: billing client connected OK`

That log line is the final acceptance criterion for issue #19.
