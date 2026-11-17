# Releasing a new SAGANA version

The permanent addresses never change:

- Website and QR code: https://sagana-landing.vercel.app (the QR opens `/get`)
- APK download button: `/download`, which serves the newest `SAGANA.apk` from this repo's GitHub Releases

Releasing is these steps. **Nothing in the `SAGANA-Landing` repo needs to change.**

1. **Raise the version** in `pubspec.yaml`, e.g. `version: 1.0.1+3`.
   The number after `+` (the build number) must be higher than every earlier release.
2. **Test** the changes (`flutter analyze`, `flutter test`).
3. **Build** the signed APK: `flutter build apk --release`.
   It is signed with the permanent key from `android/key.properties`. If that file is missing the build stops;
   restore it from your backup (see `SAGANA-signing\BACKUP-README.txt`).
4. **Rename** `build\app\outputs\flutter-apk\app-release.apk` to exactly **`SAGANA.apk`**.
5. **Install it on a phone** over the previous version and check it opens and signs in.
6. **Publish on GitHub**: `Drhylicious/SAGANA` -> Releases -> Draft a new release.
   Tag `v1.0.1`, title `1.0.1`, a short description, attach `SAGANA.apk`, then Publish.
   (Use *pre-release* to test the link first; pre-releases are not served as "latest".)
7. **Check the landing page** shows the new version, size and date, and that `/download` downloads the file.
8. **Tell installed apps**: edit and run `supabase_schema/supabase_schema_app_release_02_publish_release.sql`
   in the Supabase SQL editor (version name, build number, notes).
   From then on, every phone that opens the app online is offered the update.
   - `min_supported_build = 1`: the update is optional ("Later" hides it for a day).
   - `min_supported_build = <this build>`: older apps are blocked until they update. Use only when the
     release depends on database changes older apps cannot work with.
9. **Optional:** send a Broadcast Announcement in the app that points to the website. This also reaches
   phones that still have a version without the update check.

To pull back a bad release: `UPDATE public.app_releases SET is_active = false WHERE build_number = <n>;`
and mark the GitHub release as a pre-release (or delete it).

## One-time setup

- Run `supabase_schema/supabase_schema_app_release_01_update_check.sql` once in the Supabase SQL editor.
- The release key lives in `C:\Users\Administrator\SAGANA-signing\`. Copy that folder to two safe places off this PC
  (see `BACKUP-README.txt` in it). Without the key, nobody can update the app in place.
