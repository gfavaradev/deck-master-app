# Dependency Upgrade Scoreboard

Generated: 2026-05-19 | Base: main @ deck_master v1.3.2+14

## Major Version Bumps

| Package | Current | Target | Risk | Status | Result |
|---|---|---|---|---|---|
| `fl_chart` | 0.69.2 | 1.2.0 | HIGH | 🚫 blocked | Needs Bash/WebFetch permissions in worktree |
| `package_info_plus` | 9.0.1 | 10.1.0 | MEDIUM | ❌ fail | `win32` conflict with `file_picker ^11` |
| `sign_in_with_apple` | 7.0.1 | 8.0.0 | MEDIUM | ✅ pass | Dead dependency — pubspec bump only |

## Minor / Patch Batch

| Packages | Status | Result |
|---|---|---|
| cloud_firestore, firebase_*, flutter_secure_storage, flutter_svg, purchases_flutter | ✅ pass | 21 packages resolved, analyze clean |

---

## Detailed Results

### ✅ MERGED — Minor/patch batch (8 packages)

All 8 constraints bumped in `pubspec.yaml`. `flutter pub get` resolved 21 packages.
`flutter analyze --no-pub` returned 16 pre-existing issues only (12 from absent
`app_secrets.dart`, 4 from `scripts/` referencing `firebase_storage`). Zero
issues introduced by the upgrade.

**Packages upgraded:**
- `cloud_firestore` 6.3.0 → 6.4.1
- `firebase_app_check` 0.4.3 → 0.4.4+1
- `firebase_auth` 6.4.0 → 6.5.1
- `firebase_core` 4.7.0 → 4.9.0
- `firebase_messaging` 16.2.0 → 16.2.2
- `flutter_secure_storage` 10.0.0 → 10.2.0
- `flutter_svg` 2.2.4 → 2.3.0
- `purchases_flutter` 10.0.1 → 10.1.0

### ✅ MERGED — sign_in_with_apple 7.0.1 → 8.0.0

Package is declared in `pubspec.yaml` but **never imported in any Dart file**.
Pure pubspec bump, no code migration needed. iOS entitlements already correct.
macOS `Release.entitlements` missing the Apple Sign In capability but not a
blocker since the code path is unused.

**Manual follow-up:** If macOS Apple Sign In is ever activated, add
`com.apple.developer.applesignin` to `macos/Runner/Release.entitlements` and
update the provisioning profile.

---

## Manual Review Required

### ❌ FAIL — package_info_plus 9.0.1 → 10.1.0

**Blocker:** `package_info_plus >=10.1.0` requires `win32 ^6.0.1`.
`file_picker ^11.0.2` requires `win32 ^5.9.0`. The two ranges are incompatible
and `file_picker` has no 11.x release that supports `win32 ^6.x`.

**Good news:** No Dart code migrations needed — `PackageInfo.fromPlatform()`,
`.version`, `.buildNumber` are unchanged in 10.x.

**Action:** Wait for a `file_picker` release that supports `win32 ^6.x`, then
upgrade both packages together in one PR.

### 🚫 BLOCKED — fl_chart 0.69.2 → 1.2.0

**Blocker:** The worktree agent was denied Bash and WebFetch permissions, so it
couldn't run `flutter pub get`, `flutter analyze`, or fetch the 0.69→1.x migration
guide from pub.dev.

**Risk:** fl_chart 1.x is a near-complete API rewrite. Chart widgets, data models,
and callback signatures all changed.

**Action:** Grant `Bash` and `WebFetch` permissions in `.claude/settings.json` and
re-run the agent. Or perform the migration manually:
1. Read https://pub.dev/packages/fl_chart/changelog
2. Search the codebase for `FlChart`, `BarChartGroupData`, `LineChartBarData`,
   `getTitlesWidget`, `SideTitleWidget`
3. Apply the API migrations
4. Run `flutter analyze` and `flutter test`
