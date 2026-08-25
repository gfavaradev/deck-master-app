# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Deck Master (`deck_master`, package `com.giuseppe.deckmaster`) is a Flutter app for managing TCG (trading card game) collections — Yu-Gi-Oh, Pokémon, One Piece, Magic, and several others. It targets Android, iOS, Windows, and Web. Administration (catalog, news, prices, users) lives in a separate Next.js dashboard (`deck-master-web`, `/admin`), **not** in this app. Backend support lives in Node.js scripts under `scripts/` and Firestore/Firebase.

## Commands

### Setup (run after every fresh clone or dependency bump)
```bash
flutter pub get
# Verify both files exist before building — both are gitignored:
#   lib/config/app_secrets.dart   (CardTrader JWT, Gemini key, Anthropic key, Backblaze creds)
#   .env
```

### Run
```bash
flutter run -d windows
flutter run -d chrome
flutter run -d android
flutter run -d ios
```
Default dev port is 8081 if 8080 is occupied.

### Lint / Analyze
```bash
flutter analyze
```
Lints use `package:flutter_lints/flutter.yaml`; `scripts/**` (Node.js) is excluded from analysis. Run `flutter analyze` after every multi-file refactor before declaring work done.

### Tests
```bash
flutter test test/ --no-pub --reporter=github                              # unit tests
flutter test integration_test/regression_suite.dart --no-pub --reporter=github  # integration/regression suite
flutter test test/unit/services/xp_service_test.dart                       # single test file
```
- `test/unit/` — model, constants, service, util unit tests.
- `integration_test/crashes/` — regression tests for specific past incidents (parallel downloads, album selection crash, Firestore OOM, search scope, negative-number input, UI freeze). When fixing a bug in one of these areas, check whether an existing regression test already covers it.

### Build (release)
```bash
flutter build appbundle --release        # Android Play Store
flutter build windows --release --dart-define-from-file=dart_defines.json
flutter build web --release
build_installer.bat                      # Windows: builds + packages via Inno Setup -> installer_output/
```
CI (`.github/workflows/release.yml`) runs unit + integration tests first, then restores secrets (`google-services.json`, keystore, `key.properties`, `.env` from base64 GitHub secrets), builds the App Bundle with `--build-number=${{ github.run_number }}`, and uploads to the Play Store internal track.

### Backend scripts (Node.js, under `scripts/`)
- `scripts/price_sync/index.js` — CardTrader → Firestore price sync. Raw prices are written for every CT-backed catalog; prices are embedded into catalog chunks only for yugioh/pokemon/onepiece. Runs in production as the Cloud Run Job `price-sync` (`europe-west1`, Cloud Scheduler `0 3 * * *` Europe/Rome, JWT from Secret Manager) — see `scripts/price_sync/CLOUDRUN.md` and `deploy-cloudrun.sh`. Locally: `npm start` / `npm run yugioh`, reading `CARDTRADER_JWT` from the **repo-root** `.env` plus a local `serviceAccountKey.json`. Manual single-catalog runs also available from the `deck-master-web` dashboard (`POST /api/admin/jobs/price-sync`, ~300s cap).
- `scripts/populate_firestore/index.js` — full rebuild of `yugioh_catalog` from YGOProDeck with multi-language translations, chunked to stay under Firestore's 1MB document limit. Run with `npm start`. `scripts/populate_catalog.dart` (`flutter run -t scripts/populate_catalog.dart -d chrome`) is the incremental alternative. Other TCG catalogs are managed from `deck-master-web`, not from here.
- `scripts/update_app_version/index.js` — updates the `app_config/version` Firestore doc the app reads for update prompts: `node index.js --version 1.3.8 --android-url <url> --windows-url <url> --min-version <x> --notes "<text>"`. `--version` and `--android-url` are required; the write is a merge, so pass `--notes` on every bump.
- `scripts/news_sync/index.js` — daily RSS pull (sources in `sources.js`) into `news_drafts` with `status: "pending"`; publishing to `news` is a manual approval in `deck-master-web`. Cron: `0 4 * * *`.

## Architecture

### Layers
- **`lib/models/`** — domain types: `card_model`, `collection_model`, `album_model`, `user_model`, `wishlist_model`, `magic_models` (Scryfall-shaped).
- **`lib/services/`** — all business logic and I/O; pages should call services, not Firestore/SQLite directly. Notable groupings:
  - *Local/cloud data*: `database_helper.dart` (sqflite; use FFI on Windows; use `rawQuery()` for PRAGMA statements — `db.execute()` doesn't work for those), `firestore_service.dart`, `sync_service.dart`, `background_download_service.dart`, `data_repository.dart`.
  - *External card/price APIs*: `scryfall_service.dart` (Magic), `cardtrader_service.dart` (reads cached CardTrader prices for the card UI; price *syncing* runs server-side — Cloud Run Job `price-sync` on a schedule, plus a manual endpoint in `deck-master-web`), `price_alert_service.dart`. Scryfall and similar requests must always send a `User-Agent` header.
  - *Auth*: `auth_service.dart` (Google/Facebook/Apple/Email, platform-aware via `PlatformHelper`), `user_service.dart`.
  - *Monetization*: `ad_service.dart` (Google Mobile Ads — init is deferred ~3s after splash to avoid frame stalls), `revenue_cat_service.dart` (IAP/subscriptions).
  - *AI*: `claude_service.dart` (Anthropic API, used by the AI Deck Builder page).
  - *Misc*: `notification_service.dart` (FCM + local), `backblaze_service.dart` (B2 backups), `image_upload_service.dart`, `export_service.dart`, `update_service.dart`, `xp_service.dart`, `review_service.dart`, `exchange_rate_service.dart`, `language_service.dart`, `app_preferences.dart`.
- **`lib/pages/`** — screens, grouped by feature: auth/onboarding, core catalog/card browsing, collections & decks, profile/settings/IAP. (Admin screens have been removed — administration is the external `deck-master-web` dashboard.)
- **`lib/utils/platform_helper.dart`** — single source of truth for platform/feature gating (`isWindows/isMobile/isDesktop/isWeb`, `supportsFacebookAuth`, `supportsAppleSignIn`, etc.) and adaptive layout values. Always degrade gracefully through this helper rather than ad hoc `Platform.is*` checks.

### App bootstrap (`lib/main.dart`)
1. `FlutterNativeSplash.preserve()` before anything else (avoids an Android 12+ splash zoom-out artifact).
2. Image cache capped at 30MB debug / 60MB release to avoid OOM on constrained Android devices.
3. Firebase init via `DefaultFirebaseOptions.currentPlatform`; AppCheck only activated in release builds; Firestore on-disk persistence is disabled (SQLite is used as the local cache/source of truth instead).
4. `AppPreferences.init()` is the only blocking init; ads, background downloads, and notifications init asynchronously and ads are deliberately delayed ~3s.
5. Theme is Material 3 dark (gold primary / blue secondary); locale switching is reactive via `AppPreferences.localeNotifier`.

### State management
Provider (`provider` package) for app-level state (preferences, locale). No Bloc/Riverpod in this codebase.

### Catalog pagination
Catalog browsing loads in 100-card pages with an 80%-scroll prefetch threshold, client-side sort maintained across pages, and search resets pagination — see `CATALOG_PERFORMANCE.md` for the full rationale. Don't reintroduce single-shot full-catalog queries; this was an explicit fix for Android OOM/jank.

### Firestore data model & security (`firestore.rules`, `storage.rules`)
- Per-TCG catalog collections (`yugioh_catalog`, `pokemon_catalog`, `magic_catalog`, etc.) are readable by any authenticated user, writable only by admins (email-allowlisted in rules).
- `cardtrader_prices/{catalog}` holds raw price data; price values are also embedded directly into catalog chunks for yugioh/pokemon/onepiece by `price_sync`.
- `app_config/*` holds feature flags, version/update info, changelog; `news/*` is the news feed.
- User-owned data (collections, decks, wishlists) is scoped by `request.auth.uid`.
- For SQL queries involving `set_id`, use a `COALESCE` fallback for surrogate-ID safety.

### Localization
`l10n.yaml` drives codegen from `lib/l10n/app_it.arb` (template) and `app_en.arb` into `AppLocalizations`. Italian is the primary/template locale; English is the secondary. Access via `AppLocalizations.of(context)!.key`.

## Build Environment (Windows)
- PowerShell host; `Expand-Archive` fails on large ZIPs — use 7-Zip or `tar` instead.
- Firebase C++ SDK required version: 13.5.0 (not 12.7.0).
- Avoid downloading to `C:\` root due to permission issues — use project-local paths.
- For SSL revocation errors, use `curl --ssl-no-revoke` or equivalent; NuGet packages hit the same SSL/permission issues as the Firebase SDK — download manually to a project-local path if automatic fetch fails.
- Inno Setup (or equivalent) must be installed before the Windows packaging step — verify it exists before starting a Windows build.
- Be aware of OneDrive Files-On-Demand virtualization issues with large files — keep large assets/models outside OneDrive-synced folders.

## Android/Flutter Conventions & Gotchas
- Never change signing config from release to debug — Google Sign-In requires release signing.
- Firestore: avoid parallel downloads and oversized collection queries (causes Android heap OOM); batch/sequence reads to prevent UI freezing and OOM crashes.
- `DropdownButtonFormField` with `initialValue`/`value` is unreliable — use a controlled `DropdownButton` with an explicit state variable instead.
- Use `SizedBox(height: N)` for vertical spacing, never a bare `height(N)`.
- Verify third-party package import paths (e.g. `flutter_markdown_plus`) against the installed package's actual export path before use — wrong paths cause silent compile failures.
- `file_picker` API has changed across major versions — check current method signatures before editing; incorrect reverts cause regressions.
- When debugging Firebase auth, verify SHA-1 fingerprints AND that `google-services.json` is current.
- Cloudinary uploads: pass `folder` as a separate parameter, never embed slashes in `public_id`.

## Python Backend (where applicable)
- Use absolute imports from the project root, not relative imports — relative imports break when run from a different working directory.
- Always verify package names before installing (e.g. PDF support uses the `pymupdf` package, imported as `fitz` — not a package literally named `fitz`).
- Use `load_dotenv(override=True)` so `.env` values take precedence over system env vars.
- Before starting servers, check if the target port is free; fall back to the next available port.
- With PyTorch/CUDA, explicitly call `.to(device)` and verify GPU usage.

## MCP Servers
Configured for Claude Code in this project (`.mcp.json`, project-scoped, plus one local-only entry). Approve project-scoped servers on first run with `claude` in this directory.

| Server | Scope | Purpose |
|---|---|---|
| `firebase` (`firebase mcp --dir <repo>`) | project | Direct access to this project's Firestore/Auth/Storage (auto-detected from `firebase.json`); use instead of writing one-off admin scripts to inspect/query catalog or user data. |
| `mobile` (`@mobilenext/mobile-mcp`) | project | Drives Android devices/emulators (via `adb`) and iOS simulators (via `xcrun simctl`) — tap/swipe/screenshot for verifying mobile UI changes on-device instead of only relying on widget tests. |
| `playwright` (`@playwright/mcp`) | project | Browser automation for the web build/companion site (`site/`, Flutter Web output) — use for verifying frontend changes that can't be checked with `flutter analyze`/unit tests alone. |
| `git` (`uvx mcp-server-git --repository <repo>`) | project | Structured git log/diff/blame/status tools as MCP calls rather than parsing raw `git` CLI output — useful for tracing history during the crash-investigation workflow below. |
| `memory` (`@modelcontextprotocol/server-memory`) | project | A generic in-session knowledge-graph scratchpad for the MCP client — separate from Claude Code's own file-based auto-memory under `~/.claude/projects/.../memory/`; don't confuse the two. |
| `github` (`https://api.githubcopilot.com/mcp/`) | local (private, not committed) | Issue/PR/CI access beyond what `gh`/git already cover. Requires OAuth login on first use in an interactive session — `gh` CLI itself is not installed on this machine, so prefer this MCP server or install `gh` for GitHub operations. |

Considered but not added: a Sourcegraph code-search MCP server (`sourcegraph-mcp-server`) — skipped because it needs a `SOURCEGRAPH_URL`/`SOURCEGRAPH_TOKEN` for a self-hosted or cloud instance that isn't in use here. Revisit if that changes.

No secrets are stored in `.mcp.json` for the project-scoped servers — they just invoke local CLIs (`firebase`, `npx`). Don't add servers requiring API keys/tokens at project scope; use `-s local` (or env vars outside the repo) for anything credentialed, as was done for `github`.

For structured web research use the built-in `WebSearch`/`WebFetch` tools rather than a dedicated search MCP server. For a second opinion on a diff, use the `/code-review` skill (supports `ultra` for a multi-agent cloud review) rather than a separate dual-model MCP server — neither a "Kindly" nor a "Lad" MCP server is configured or known here; don't assume they exist without a concrete package/URL to add.

## Spec-Driven Development for non-trivial work
Before implementing a feature or refactor big enough to span multiple files/services, copy `REQUIREMENTS.md` (repo root) to a feature-specific file and fill it in — objective, constraints, acceptance criteria — before delegating implementation. Skip this for small, single-file fixes.

## TDD workflow
For bug fixes and new logic in `lib/services/`, `lib/models/`, and `lib/utils/`, write or update the failing test first (`test/unit/...`), confirm it fails for the expected reason, then implement until it passes. This is especially important for areas covered by `integration_test/crashes/` regression tests — check for an existing test before writing a new one.

## Project Skills (`.claude/skills/`)
These are invocable with `/<name>` and encode the recurring workflows for this repo — prefer them over re-deriving the commands by hand:
- `/flutter-build` — build a release artifact (`android`/`ios`/`windows`/`web`), including the secrets preflight (`app_secrets.dart`, `.env`, `dart_defines.json` for Windows), the Inno Setup packaging step, and what pushing to `main` triggers in CI.
- `/flutter-test` — run the two CI test commands, the on-device `flutter drive` variant, or a single test file; explains how `test/regression_tests.dart` and `integration_test/regression_suite.dart` mirror each other.
- `/price-sync` — run, redeploy, or debug the CardTrader price sync (local script, Cloud Run Job, dashboard endpoint).
- `/populate-catalog` — rebuild or incrementally top up `yugioh_catalog` from YGOProDeck.
- `/news-sync` — run or extend the daily news feed sync into `news_drafts`.
- `/bump-app-version` — run `scripts/update_app_version` to publish a new version/update-prompt to `app_config/version`.

Generic (non-project) skills worth reaching for here: `/run` to launch and visually verify the app after a UI change, `/code-review` before considering a non-trivial change done, `/security-review` before touching auth/Firestore rules/secrets handling.

Vendored upstream skills (`firebase/agent-skills`, `flutter/skills`) are managed with `npx skills add/update/remove` and tracked in `skills-lock.json` — don't hand-edit them, or the next `skills update` will clobber the change.
**Caveat on `firebase-auth-basics`:** it tells you to declare an `auth` block in `firebase.json` and run `firebase deploy --only auth`. Don't. This project has no `auth` block — providers (Google, Facebook, Apple, Email) are configured in the Firebase Console, and Facebook/Apple can't be expressed via the CLI at all, so deploying a generated block would push a provider config that omits them. Use the skill for client-SDK and rules guidance only.

## Workflow Rules
- **Crash investigation:** before suggesting any code change, trace the full data flow first — every call site, data sizes involved, concurrency model — and report findings before proposing fixes.
- **Debugging:** if a fix doesn't resolve the issue after 2 attempts, stop and add diagnostic logging/counters before trying more fixes; don't assume root cause without verifying via logs.
- **Dependency updates:** before changing versions, produce a risk assessment (breaking changes, affected modules, verification checklist) and get approval before making changes. After bumping, re-verify `app_secrets.dart`/`.env` still exist, and run a full build + launch check. Check Flutter API deprecations against the target SDK before editing call sites.
- **Refactoring:** grep the whole codebase for references before removing/renaming any constant or function; run import checks and smoke tests after; never change a signature silently — call out what changed.
- Catalog download, image migration, and price sync are tightly coupled — check all three for regressions when fixing bugs in any one of them.
