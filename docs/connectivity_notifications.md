# Unified connectivity notifications

Current presentation: see **Compact card update** below. It supersedes the original screen-description design and wording documented in the earlier sections.

Implemented against `C:\Users\Administrator\Downloads\MD\guidelines.md` and the supplied reference images.

## Implementation

- One application-level floating card replaces the old restoration pill and inline connectivity/cached-data banners. It is outside page layout, passes pointer events through, and does not move the dashboard greeting or other page content.
- Offline and restored states share one rounded layout. Offline uses the theme's red error container; restored uses green. English titles are “You're Offline” and “You're Back Online”. English and Tagalog content is localized.
- Offline remains visible while disconnected. Restored replaces it for 12 seconds. Repeated identical connectivity events do not create additional notices or restart timers.
- The card includes separate status text and a short, justified description of the active screen. GoRouter's active leaf handles primary, secondary, and nested routes. A page observer also covers the six direct Navigator pushes: farm, address, cooperative and delivery maps, and distribution history by year. Dialogs retain the underlying page's description.
- Manager, Officer, and Farmer messages explain supported local records and synchronization. Buyer and signed-out/guest messages describe connectivity only, without claiming offline data access, local transactions, or synchronization.
- Existing connectivity detection, caches, record queues, automatic/manual synchronization, and role permissions are unchanged. Feature-specific load failures, retry actions, and transaction restrictions remain intact.

The duplicate presentation came from the root restoration pill appearing while page-level saved-data notices remained visible. The dashboard also inserted its notice before the greeting. The root now owns both states; the legacy notice widgets return zero-size placeholders for existing callers, and the dashboard's notice/subscription were removed. Two conditional banner gaps and an independent loan-request banner were removed as well.

## Complete file list for this change

Other pre-existing workspace changes belong to earlier work and are not included here.

| File | Purpose |
| --- | --- |
| `lib/main.dart` | Connect the shared overlay, router, and page observer. |
| `lib/presentation/navigation/app_router.dart` | Accept and attach Navigator observers. |
| `lib/presentation/navigation/connectivity_page_observer.dart` (new) | Track direct page pushes without treating dialogs as new screens. |
| `lib/presentation/navigation/connectivity_screen_description.dart` (new) | Map active routes and direct pages to localized descriptions. |
| `lib/presentation/widgets/connectivity_overlay.dart` | Shared floating red/green card, transition timing, role wording, and justified description. |
| `lib/presentation/widgets/cached_data_notice.dart` | Retire inline cached-data notification rendering. |
| `lib/presentation/widgets/shared_widgets.dart` | Retire inline OfflineStatusCard rendering. |
| `lib/presentation/widgets/pending_applicant_views.dart` | Remove the conditional banner gap and unused import. |
| `lib/presentation/screens/admin/admin_dashboard_screen.dart` | Remove the inline dashboard notice and its unused connectivity listener. |
| `lib/presentation/screens/admin/loan_requests_screen.dart` | Remove a separate inline offline banner while retaining action restrictions. |
| `lib/presentation/screens/admin/admin_order_detail_screen.dart` | Identify its delivery-map page for the shared description. |
| `lib/presentation/screens/admin/admin_program_order_detail_screen.dart` | Identify its delivery-map page. |
| `lib/presentation/screens/admin/balik_tangkilik_management_screen.dart` | Identify the distribution-year page. |
| `lib/presentation/screens/admin/cooperative_details_screen.dart` | Identify the cooperative-map page. |
| `lib/presentation/screens/buyer/add_edit_address_screen.dart` | Identify the address-map page. |
| `lib/presentation/screens/farmer/edit_farm_details_screen.dart` | Identify the farm-map page. |
| `lib/presentation/screens/farmer/my_contribution_screen.dart` | Remove the conditional inline banner gap. |
| `lib/core/l10n/app_en.arb` | Add English status messages and screen descriptions. |
| `lib/core/l10n/app_tl.arb` | Add matching Tagalog messages and descriptions. |
| `lib/core/l10n/app_localizations.dart` | Regenerate localization declarations. |
| `lib/core/l10n/app_localizations_en.dart` | Regenerate English localization implementation. |
| `lib/core/l10n/app_localizations_tl.dart` | Regenerate Tagalog localization implementation. |
| `docs/connectivity_notifications.md` (new) | Record implementation, file inventory, and verification limits. |

## Database and approvals

No SQL scripts, migrations, schema, RPC, trigger, RLS, or Supabase configuration changes are required for this presentation change. No database queries or manual Supabase checks are required. No decisions or approvals remain pending.

## Verification performed

Reviewed the connectivity/synchronization architecture, role exclusions, route configuration, six direct page pushes, legacy banner call sites, localization content, timer disposal, and overlay layout in source. Generated localizations successfully with `flutter gen-l10n` and formatted the edited Dart source with `dart format`.

No tests, `flutter analyze`, builds, browser checks, or runtime verification were run for this change, as requested. Visual behavior and runtime correctness have therefore not been demonstrated. The older `docs/flutter_analysis.log` belongs to earlier work and does not validate these changes. No additional testing is required from the user by this report.

## Message wording update

Updated the four English message bodies to the user's exact supplied wording and added corresponding Tagalog translations. Reviewed the supplied card images and existing Manager notification path before editing. The shared card already replaces offline with restored state, ignores repeated identical events, and follows primary and secondary navigation. No active separate Manager restoration toast was found; the old `connectionRestored` localization key has no presentation caller.

Files modified in this wording update only:

- `lib/core/l10n/app_en.arb`: exact English wording for Manager/Officer/Farmer and Buyer, offline and online.
- `lib/core/l10n/app_tl.arb`: corresponding Tagalog translations.
- `lib/core/l10n/app_localizations.dart`: regenerated English documentation for the four messages.
- `lib/core/l10n/app_localizations_en.dart`: regenerated English Dart getters.
- `lib/core/l10n/app_localizations_tl.dart`: regenerated Tagalog Dart getters.
- `docs/connectivity_notifications.md`: this update record.

Notification layout, titles, screen descriptions, timing, navigation, detection, role selection, and automatic/manual synchronization were preserved. No Buyer offline access, transactions, or synchronization were introduced. No SQL, migrations, Supabase checks, or approvals are required. Verification was limited to source review and localization generation; no tests, analyzer, builds, or runtime checks were run or requested.

## Compact card update

Reviewed the latest screenshots and existing shared overlay before editing. The notification now contains only its state icon, title, main message, and close control. The horizontal divider and screen description have been removed from the rendered card.

- Width is 84% of the available safe-area width, capped at 340 pixels, with at least 24-pixel horizontal safe-area margins. Padding, icon, corner radius, shadow, and typography are more compact; red/green state colors are retained.
- The floating card stays below the top toolbar without allocating page space. A close button lets users immediately uncover content beneath it. Other areas remain interactive without a modal barrier. For large text or short windows, the card height is bounded and its contents can scroll.
- Manager, Officer, and Farmer offline wording: “You're viewing saved data. New records are saved locally and sync when you're back online. Some features require internet.” Restored wording: “Your connection is restored. Your offline records are now syncing.”
- Buyer offline wording: “Please connect to the internet to use SAGANA.” Restored wording: “Your internet connection is restored. You can now continue using SAGANA.” Matching Tagalog translations were updated.
- Only one card is rendered. A new connectivity state replaces the previous one and makes the card visible again after dismissal. The existing 12-second restored timeout is retained; offline remains visible until dismissed or connectivity returns.
- The shared root overlay still covers primary, secondary, and nested pages. Its no-longer-needed page-description observer registration was removed from app setup. Router changes still refresh role-specific wording.
- Connectivity detection, role selection, offline data access, queued writes, and automatic/manual synchronization were not changed. Buyer receives no offline or synchronization functionality.

Complete file list for this compact-card update:

| File | Change |
| --- | --- |
| `lib/presentation/widgets/connectivity_overlay.dart` | Compact responsive card; remove divider/description; add dismissal and scrollable height bounds. |
| `lib/main.dart` | Remove page-description observer wiring and the overlay's obsolete observer argument. |
| `lib/core/l10n/app_en.arb` | Shorter role-specific English messages. |
| `lib/core/l10n/app_tl.arb` | Matching Tagalog messages. |
| `lib/core/l10n/app_localizations.dart` | Regenerated message documentation. |
| `lib/core/l10n/app_localizations_en.dart` | Regenerated English message getters. |
| `lib/core/l10n/app_localizations_tl.dart` | Regenerated Tagalog message getters. |
| `docs/connectivity_notifications.md` | Current implementation and verification record. |

Source review, `dart format` for the two edited application Dart files, and `flutter gen-l10n` completed. No tests, analyzer, builds, or runtime/visual checks were run. No additional testing is requested. No database changes, SQL scripts, Supabase checks, or decisions/approvals are required.

## Close-button tooltip exception fix

The supplied exception identifies the close IconButton's RawTooltip failing with “No Overlay widget found”. The notification is created in `MaterialApp.builder`, above the Navigator, so the Navigator's Overlay is a descendant rather than an ancestor of the notification. The compact-card change introduced this tooltip without supplying the required ancestor.

Wrapped the notification's existing root Stack with Flutter's `Overlay.wrap`. This provides a real Overlay ancestor for the tooltip while retaining the routed child, floating card position, dismissal, wording, role restrictions, and synchronization behavior. The extreme RenderFlex overflow is consistent with Flutter's large error placeholder being inserted in the header row after the tooltip assertion.

Files modified for this fix: `lib/presentation/widgets/connectivity_overlay.dart` and `docs/connectivity_notifications.md`. Reviewed the exception, widget ancestry, Flutter SDK tooltip assertion, and the installed SDK's `Overlay.wrap` implementation. Dart formatting completed. No tests, analyzer, or runtime checks were run, in line with the user's standing instruction. No database changes, SQL, Supabase checks, or approvals are required.
