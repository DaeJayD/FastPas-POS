# Release preparation

## Verified development backend

The development project has all eleven repository migrations installed. On 13 November 2026, a clean replay matched 20 tables and 42 functions, including columns, constraints, policies, function bodies and execution grants. The hosted migration versions now match the local filenames. Earlier history records are retained in the ignored `config/release-schema-before.local.json`.

The application-data snapshot in `config/phase10-backup.local.json` contains all 20 application tables, their rows, schema evidence, migration statements and Auth identity references. Treat the snapshot as private business data and keep its off-site copy under the owner's control.

```powershell
node supabase/tests/restore_rehearsal.mjs config/phase10-backup.local.json
```

This command restores into isolated in-memory PostgreSQL, replays the repository migrations, checks table digests and exercises receipt retry and access isolation. The 13 November run restored 164 rows and passed 100 checks. Its report is `config/phase10-restore.local.json`.

Full disaster recovery also requires Auth records and settings, encryption/signing keys, external services and Storage files. Rehearse a managed restore into an independent project and verify sign-in and file recovery before a real store pilot. Supabase documents its database backup scope and separate Storage-file requirements. [Database backups](https://supabase.com/docs/guides/platform/backups)

## Android signing

Copy `config/android-signing.example.properties` to the ignored `android/key.properties` and fill in the upload keystore path, alias and passwords locally. Relative keystore paths resolve from `android/`. The owner needs a backed-up upload key and the final application ID for store updates. [Android app signing](https://developer.android.com/studio/publish/app-signing)

Set the application ID for the release invocation and use the configured backend values.

```powershell
$env:ORG_GRADLE_PROJECT_fastpasApplicationId = 'com.yourcompany.fastpas'
flutter build appbundle --release --dart-define-from-file=config/supabase.local.json
Remove-Item Env:ORG_GRADLE_PROJECT_fastpasApplicationId
```

Replace the example application ID with the owner's chosen store ID. Build validation requires release signing values and rejects the development `com.example.*` ID. For a separate local signing-properties file, set `ORG_GRADLE_PROJECT_fastpasSigningProperties` to its absolute path.

The current profile install uses the development identifier and signing certificate. A distinct store application ID is a separate installation with its own local data. Complete pending uploads on the development installation before retiring it.

The missing-signing release probe reached the intended validation error on 13 November 2026. The positive temporary-key bundle check and the profile regression build remain pending. An initial probe also encountered a stale generated integration-test registrant; the normal dependency-generation build resolved that compilation failure.

## Remaining acceptance

- Complete the physical two-phone outage, process restart and reconnect checks in [device acceptance](DEVICE_ACCEPTANCE.md).
- Verify real email verification and password recovery links with the app running and closed.
- Exercise the chosen production backend, Auth settings, tenant isolation and managed backup recovery.
- Choose the store application ID, create and back up the owner-controlled upload key, and prepare store metadata and privacy disclosures.
- Review the existing Auth password-protection and database-performance advisories.
- Validate the production-signed bundle on physical Android hardware before publication.

The development toolchain still reports Android Gradle Plugin and Kotlin deprecation warnings. Production publication remains pending these acceptance steps and the owner's store setup.
