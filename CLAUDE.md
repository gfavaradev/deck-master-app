# deck-master-app

## Build Environment
- Windows host with PowerShell; Expand-Archive fails on large ZIPs - use 7-Zip or tar instead
- Firebase C++ SDK required version: 13.5.0 (not 12.7.0)
- Avoid downloading to C:\ root due to permission issues - use project-local paths
- For SSL revocation errors, use `curl --ssl-no-revoke` or equivalent
- NuGet packages are subject to the same SSL/permission issues as the Firebase SDK - download manually to a project-local path if the automatic fetch fails
- Inno Setup (or equivalent installer tooling) must be installed before the Windows packaging step - verify it exists before starting a Windows build

## Environment & Dependencies
- Always verify package names before installing (e.g., PyMuPDF vs fitz — use `pymupdf`, imported as `fitz`)
- Use `load_dotenv(override=True)` to ensure .env values take precedence over system env vars
- For PDF support in Python, use `pymupdf` package (imported as `fitz`), not a package literally named `fitz`
- Before starting servers, check if the target port is free; fallback to next available port
- When working with PyTorch/CUDA, explicitly call `.to(device)` and verify GPU usage
- For Windows: be aware of OneDrive Files-On-Demand virtualization issues with large model files — move models outside OneDrive-synced folders

## Crash Investigation
- **Before suggesting any code change:** use a task agent to trace the full data flow — identify every call site, data sizes involved, and the concurrency model. Report findings first, then propose fixes.

## Flutter/Mobile Specifics
- For sqflite on Android, use `rawQuery()` not `db.execute()` for PRAGMA statements like WAL mode
- Always add User-Agent headers to Scryfall and similar API requests
- When debugging Firebase auth, verify SHA-1 fingerprints AND google-services.json is current
- Default to port 8081 if 8080 is occupied

## Android/Flutter Conventions
- Never change signing config from release to debug - Google Sign In requires release signing
- Firestore: avoid parallel downloads and oversized collection queries (causes Android heap OOM)
- Batch/sequence Firestore reads to prevent UI freezing and OOM crashes
- Required local files: app_secrets.dart AND .env — both are gitignored and both must exist before building; check for both after any fresh clone or dep update
- `DropdownButtonFormField` with `initialValue`/`value` is unreliable — use a controlled `DropdownButton` with an explicit state variable instead
- Use `SizedBox(height: N)` for vertical spacing, never bare `height(N)`
- Third-party package import paths (e.g. `flutter_markdown_plus`) must be verified against the installed package's actual export path before use — wrong paths cause silent compile failures
- `file_picker` API: always check current method signatures before editing — the API changed across major versions and incorrect reverts cause regressions

## Python Backend
- Use absolute imports from the project root, not relative imports — relative imports break when the backend is run from a different working directory

## Debugging Workflow
- When a fix doesn't resolve the issue after 2 attempts, STOP and add diagnostic logging/counters before trying more fixes
- Don't assume root cause — verify with logs (the 33% download freeze and Cloudinary 'nothing to migrate' both needed diagnostics first)

## Dependency Updates
- **Before making any changes:** produce a risk assessment — list every breaking change between current and target versions, identify which app modules use each changed API, and propose a verification checklist. Do NOT make changes until the user approves the plan.
- After bumping dependencies, always verify app_secrets.dart, .env, and other gitignored config files still exist
- Run a full build + launch verification before declaring updates done
- Check Flutter API deprecations (e.g., DropdownButtonFormField initialValue vs value) against the target SDK version before editing

## Refactoring Rules
- When removing or renaming constants/functions, grep the entire codebase for references BEFORE committing the change
- After any refactor, run import checks and basic smoke tests
- Never introduce regressions silently — call out any signatures or symbols that were changed

## Project Conventions & Known Gotchas

## Flutter/TCG Project Conventions
- Always run `flutter analyze` and existing tests after multi-file refactors before declaring done
- When fixing bugs, check for regressions in related code paths (catalog download, image migration, price sync are tightly coupled)
- Cloudinary uploads: pass `folder` as a separate parameter, never embed slashes in `public_id`
- Scryfall API requests must include a User-Agent header
- For SQL queries involving set_id, use COALESCE fallback for surrogate ID safety
