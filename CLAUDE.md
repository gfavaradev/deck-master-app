# deck-master-app

## Build Environment
- Windows host with PowerShell; Expand-Archive fails on large ZIPs - use 7-Zip or tar instead
- Firebase C++ SDK required version: 13.5.0 (not 12.7.0)
- Avoid downloading to C:\ root due to permission issues - use project-local paths
- For SSL revocation errors, use `curl --ssl-no-revoke` or equivalent
- NuGet packages are subject to the same SSL/permission issues as the Firebase SDK - download manually to a project-local path if the automatic fetch fails
- Inno Setup (or equivalent installer tooling) must be installed before the Windows packaging step - verify it exists before starting a Windows build

## Crash Investigation
- **Before suggesting any code change:** use a task agent to trace the full data flow — identify every call site, data sizes involved, and the concurrency model. Report findings first, then propose fixes.

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

## Dependency Updates
- **Before making any changes:** produce a risk assessment — list every breaking change between current and target versions, identify which app modules use each changed API, and propose a verification checklist. Do NOT make changes until the user approves the plan.
- After bumping dependencies, always verify app_secrets.dart, .env, and other gitignored config files still exist
- Run a full build + launch verification before declaring updates done
- Check Flutter API deprecations (e.g., DropdownButtonFormField initialValue vs value) against the target SDK version before editing
