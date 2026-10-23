# Application structure

The normal entry point is `lib/main.dart`, which delegates to the business workspace app. It reads local build configuration and initializes Supabase Auth with PKCE. `lib/preview/main.dart` is a separate sample entry point with a local read-only transport. The normal entry point never enables that transport.

`lib/workspaces/main.dart` implements the default multi-business app using the `pos_*` schema. It supports owner onboarding, business selection, staff invitation codes, and branch access. `workspace_account.dart` owns password recovery state and serializes callback exchanges before screens subscribe. `app_links` delivers initial and running-app links; automatic SDK URI handling is disabled to avoid duplicate exchanges. See [fresh setup](SETUP.md) and [business workspaces](BUSINESSES.md).

`lib/legacy_main.dart` retains the old single-store entry point. Workspace navigation cannot enter its routes. Later feature phases will adapt those screens to the new database; any optional old-record import needs a verified tenant migration first.

The staged branch flow uses `hybrid/local_store.dart` for scoped SQLite persistence and atomic local cash checkout, `hybrid/sync_service.dart` for permission checks and durable upload processing, and `hybrid/hybrid_pos_screen.dart` for cash selling and sync status. The additive cash-sale migration supplies server transactions. See [hybrid operation](HYBRID.md) for the offline access window, shortage policy, and remaining features.

| Area | Responsibility |
|---|---|
| `auth/employee_login_repository.dart` | Isolate the existing sign-in contract until the identity migration |
| `core/pos_session.dart` | Typed identity carried between screens |
| `core/store_navigation.dart` | Return to product Home and sign out consistently |
| `catalog/catalog_source.dart` | Typed branch/product reads and catalog pagination |
| `branches/branch_repository.dart` | Branch identities, assigned brands, stock warnings, calendar reads |
| `branches/branch_screen.dart` | Shared branch management layout |
| `inventory/branchinventory/branch_inventory_screen.dart` | Shared branch brand list |
| `branches/calendar_repository.dart` | Calendar reads and writes |
| `inventory/stock_repository.dart` | Validate stock adjustments and adapt existing movement writes |
| `sales/sale_models.dart` | Typed sale lines, totals and write request |
| `sales/sales_repository.dart` | Current sale persistence and receipt reads |
| `reports/report_repository.dart` | Report queries, period boundaries and aggregation |

The six old city-specific route names are small compatibility adapters around the shared branch screens. Branch selection uses saved identities, so adding a branch does not require copying another screen. Obsolete parallel selling screens and an unused hard-coded report mockup have been removed.

Refactoring is incremental. Older catalog forms, staff pages, exports, and attendance still contain some direct queries. Move those boundaries when their corresponding feature phases define the new schema; avoid replacing unverified contracts merely to rename files. The remaining integrity and identity work is recorded in [the database inventory](DATABASE.md).

## Toolchain baseline

The project targets Flutter 3.47.4 / Dart 3.13, Gradle 8.14.3, Android Gradle Plugin 8.11.1, Kotlin 2.2.21 and Java 17 bytecode. Gradle uses the Android Studio JDK on this machine. The wrapper distribution has a SHA-256 check. Worker count and heap limits are bounded to avoid duplicate large compiler processes.

These versions meet the installed Flutter toolchain's minimum checks. Flutter still warns that a future upgrade to Gradle/AGP 9 and newer Kotlin will be required. See the [Kotlin compatibility table](https://kotlinlang.org/docs/gradle-configure-project.html) and [Gradle 8.14.3 notes](https://docs.gradle.org/8.14.3/release-notes.html). Moving to AGP 9's Kotlin setup should be a deliberate toolchain change with plugin validation.

## Checks

```sh
flutter pub get
flutter analyze
flutter test --no-pub
flutter build web -t lib/preview/main.dart --no-pub --no-web-resources-cdn --no-wasm-dry-run
flutter build apk --debug --dart-define-from-file=config/supabase.local.json --no-pub
flutter test integration_test/preview_smoke_test.dart -d <android-device-id>
```

Use a debug APK for development. Release signing and physical-device acceptance belong to the release phase. The sample integration test exercises selling and branch navigation without calling a live store.

On a memory-constrained development machine, build the sample test before starting the emulator, then run the prebuilt APK. This keeps Gradle compilation and the emulator from competing for memory:

```sh
flutter build apk --debug --target-platform android-x64 -t integration_test/preview_smoke_test.dart --no-pub
flutter drive --driver=test_driver/preview_driver.dart --target=integration_test/preview_smoke_test.dart --use-application-binary=build/app/outputs/flutter-apk/app-debug.apk -d <android-emulator-id> --no-pub
```

That APK contains the test entry point. Rebuild using the normal `lib/main.dart` entry point before distributing a development app.
