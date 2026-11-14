# SAGANA enhancements: implementation and review

Reviewed against `C:/Users/Administrator/Downloads/MD/enhancements.md`, the supplied project instructions, and `CLAUDE.md`. The attached document supplies product requirements; the current user request controls verification. The explicit request to run Flutter analysis supersedes the earlier analysis restriction. No tests, builds, browser checks, or live database commands were run.

## 1. What changed or was fixed

- Fixed the two dropdown prompt compile errors: a localized expression cannot be a constant parameter default, and the parameter default had no usable `context`. The optional hint now resolves from localization inside the function.
- Cleared all analyzer diagnostics. The first run reported 2 errors, 9 warnings, and 232 informational findings. Removed unused imports/listeners, corrected context use after asynchronous calls, declared the referenced Flutter SDK dependency, updated deprecated control arguments, and applied normal const/block/interpolation fixes. Analyzer rules were not weakened and diagnostics were not suppressed.
- Completed further source corrections for dark surfaces, missing Tagalog defaults/statuses/categories/payout wording, filter accessibility, localized dates, and notification icon contrast.
- Fixed dropped-connection recovery for harvest batches and profile/crop photos. Transport failures retain the queued payload and retry identity. A lost batch response no longer triggers a destructive rollback. Replays are bound to their original account across asynchronous operations.
- Fixed the reconnect/probe race, added missing history/report read-only RPC snapshots, persisted legacy queue ownership once, and preserved original cached-data timestamps instead of treating fallback data as a fresh server response.

## 2. Review against every requirement group

| Requirement | Implementation and source review |
| --- | --- |
| Shared dark mode for Manager, Officer, Farmer, Buyer | Shared Manager-based theme tokens cover updated screens, fields, cards, menus, dialogs, sheets, date/time pickers, placeholders, and validation states. Saturated brand fills retain their readable foregrounds. |
| Simple, consistent Tagalog throughout the interface | 4857 English/Tagalog entries, including 678 additions across this task. Missing default prompts, crop details, harvest states, payout messages, built-in categories, and accessibility labels now use localization. Known notification rendering covers 75 titles and 92 body templates. |
| Manager/Officer/Farmer offline navigation and cached reads | Eligible roles reuse encrypted, account-scoped list snapshots and authenticated REST/24 explicit read-only RPC responses, including loan details and program/listing history. Routing and existing role/module restrictions remain in force. Previously retrieved data is required for a snapshot. |
| Supported offline writes retained locally | Harvests, expenses, profile/photo edits, crop-photo edits, notification changes, capital entries, loan issuance submissions, and loan payments use the existing local queues. Local records do not bypass backend authorization or validation. |
| Automatic sync after reconnect | One shared sync operation is triggered by reconnect, startup, sign-in, and resume, with periodic retries while online. Buyers are ineligible. |
| Manual Sync Now retained | Existing Dashboard controls for Manager/Officer and Home control for Farmer remain. Concurrent manual/automatic requests share the running operation. |
| Duplicate prevention and failure handling | Stable UUIDs/idempotency keys survive replay and legacy queue migration. Existing backend transaction validation remains authoritative. Rejected records stay queued with a localized failure message. Notification/photo action ordering is preserved. |
| Floating loss/restoration notices on every role/screen | Root overlay sits above the Navigator, including secondary pages/dialogs; it reserves no page layout space and ignores pointer input. Offline notice persists; restoration notice dismisses after four seconds. Inline connectivity banners no longer push content down. |
| Buyer connectivity only | Buyer requests bypass offline snapshots, cannot enter offline write queues, and do not run queue synchronization. Shared connectivity notices remain available. |

Built-in label translations affect display only. Stored category/filter values, JSON/database keys, route arguments, and transaction payloads stay independent of language. User-written names, reasons, messages, custom labels, proper names, and measurement units retain their content. Familiar technology terms such as Email and password remain where they are the clearest everyday Filipino wording. Unknown custom/future notification text is preserved rather than discarded.

## 3. SQL scripts, database changes, and migrations

No schema migration, table/RPC/function/trigger/RLS change, or database mutation was created or applied for these enhancements. The client reuses the existing `issue_loan` and `record_loan_payment` idempotency arguments, row primary keys, batch numbering, capital-total triggers, and backend role/stock/balance checks. New harvest inventory batches use the same stable request UUID in their own table; no schema change is needed for a UUID primary key.

The new [enhancements_supabase_checks.sql](enhancements_supabase_checks.sql) contains only read-only queries. Existing unrelated push-notification SQL and Firebase work were retained and are not migrations introduced by this task.

## 4. Exact Supabase checks

All exact queries and expected conditions are in [enhancements_supabase_checks.sql](enhancements_supabase_checks.sql), in this order:

1. Required table presence.
2. Loan RPC signatures, idempotency arguments, and authenticated execution privileges; optional connectivity `ping`.
3. Current loan function definitions, including authorization, member/stock/balance checks, locks, and replay lookup.
4. Primary/unique constraints for harvest, expense, capital, loan, payment, and inventory identities.
5. Equivalent unique indexes.
6. Enabled RLS and current policies for role/module/owner restrictions.
7. Enabled harvest/batch/capital maintenance triggers.
8. Presence/signatures/volatility/permissions of the 24 explicit read-only RPCs.
9. Existing duplicate loan/payment keys and incomplete/duplicate harvest-to-batch links.

These queries have not been executed against the live database. Repository SQL was inspected. Missing prerequisites must be compared with the current deployed schema; old migrations must not be reapplied blindly over newer logic.

## 5. Verification, remaining issues, and approvals

- Final command: `flutter analyze --no-pub --write=docs/flutter_analysis.log`.
- Actual result: **No issues found!** Exit code **0**; **0 errors, 0 warnings, 0 informational findings**. See [recorded analyzer output](flutter_analysis.log).
- English/Tagalog localization generation completed successfully. Source formatting completed. Static source review covered role gates, cache ownership, retry identities, replay ordering, connectivity placement, display-vs-data values, and retained manual sync controls.
- No automated tests or other testing commands were run, as requested. Test-source changes listed below are analyzer cleanup only; they do not constitute executed tests.
- Rendered UI behavior, real device disconnection/reconnection, and the live Supabase deployment were not exercised. A clean analyzer establishes static correctness; it does not prove those runtime behaviors. No runtime or database success is claimed.
- No implementation decision or approval is pending. Any repair of pre-existing database integrity problems found by the supplied read-only queries would be separate work; no such repair has been made.

## Complete modified-file inventory

237 deliverable files, including 230 Dart files. This includes the original enhancement implementation and this review/fix pass. Existing edits within shared files were retained. Unrelated pre-existing Android/Firebase configuration, push services/functions, and other untouched working-tree files are excluded. Temporary review scripts are not deliverables and were removed.

| File | Status | Task changes/purpose |
| --- | --- | --- |
| [docs/enhancements_implementation.md](../docs/enhancements_implementation.md) | Created | Requirement review, actual verification results, limits, and complete file inventory. |
| [docs/enhancements_supabase_checks.sql](../docs/enhancements_supabase_checks.sql) | Created | Exact read-only queries for live Supabase compatibility and integrity review; no migration. |
| [docs/flutter_analysis.log](../docs/flutter_analysis.log) | Created | Recorded final flutter analyze output and successful exit code. |
| [lib/core/l10n/app_en.arb](../lib/core/l10n/app_en.arb) | Modified | English source strings, notification templates, and final missing UI/accessibility labels. |
| [lib/core/l10n/app_localizations.dart](../lib/core/l10n/app_localizations.dart) | Modified | Regenerated localization accessors and language implementations. |
| [lib/core/l10n/app_localizations_en.dart](../lib/core/l10n/app_localizations_en.dart) | Modified | Regenerated localization accessors and language implementations. |
| [lib/core/l10n/app_localizations_tl.dart](../lib/core/l10n/app_localizations_tl.dart) | Modified | Regenerated localization accessors and language implementations. |
| [lib/core/l10n/app_tl.arb](../lib/core/l10n/app_tl.arb) | Modified | Simple Tagalog translations, built-in category names, payout wording, and consistent terminology. |
| [lib/core/l10n/localized_labels.dart](../lib/core/l10n/localized_labels.dart) | Created | Translate built-in display labels while preserving stored values, filter IDs, and custom names. |
| [lib/core/l10n/system_notification_text.dart](../lib/core/l10n/system_notification_text.dart) | Created | Locale-aware rendering of known database notification titles and bodies. |
| [lib/core/theme/app_theme.dart](../lib/core/theme/app_theme.dart) | Modified | Shared Manager-based picker/menu/dialog/input themes and readable dark-mode validation colors. |
| [lib/core/theme/sagana_colors.dart](../lib/core/theme/sagana_colors.dart) | Modified | Shared theme tokens and adaptive tinted surfaces. |
| [lib/core/utils/app_error_message.dart](../lib/core/utils/app_error_message.dart) | Modified | Localized offline failures and Tagalog-safe database error fallback. |
| [lib/core/utils/member_activity_label.dart](../lib/core/utils/member_activity_label.dart) | Modified | Formatting and analyzer block-syntax cleanup; pre-existing activity logic retained. |
| [lib/data/models/cooperative_delivery_model.dart](../lib/data/models/cooperative_delivery_model.dart) | Modified | Analyzer block-syntax cleanup; delivery rules retained. |
| [lib/data/models/cooperative_product_model.dart](../lib/data/models/cooperative_product_model.dart) | Modified | Analyzer block-syntax cleanup; product rules retained. |
| [lib/data/repositories/admin_loan_repository.dart](../lib/data/repositories/admin_loan_repository.dart) | Modified | Stable payment request IDs and safe queueing when connectivity drops. |
| [lib/data/repositories/admin_profile_repository.dart](../lib/data/repositories/admin_profile_repository.dart) | Modified | Propagate underlying photo-upload failures so supported connection-loss edits can queue. |
| [lib/data/repositories/buyer_address_repository.dart](../lib/data/repositories/buyer_address_repository.dart) | Modified | Remove unnecessary interpolation; retain existing address behavior and Buyer restrictions. |
| [lib/data/repositories/capital_contribution_repository.dart](../lib/data/repositories/capital_contribution_repository.dart) | Modified | Reuse contribution IDs so replay does not insert the same payment twice. |
| [lib/data/repositories/cooperative_delivery_repository.dart](../lib/data/repositories/cooperative_delivery_repository.dart) | Modified | Allow a previously retrieved delivery quote to use eligible-role snapshots; checkout writes stay server-validated. |
| [lib/data/repositories/crop_repository.dart](../lib/data/repositories/crop_repository.dart) | Modified | Preserve transport errors through photo upload/save; retain legacy callers through optional error propagation. |
| [lib/data/repositories/expense_repository.dart](../lib/data/repositories/expense_repository.dart) | Modified | Preserve expense request identity and save locally after connection loss. |
| [lib/data/repositories/farmer_profile_repository.dart](../lib/data/repositories/farmer_profile_repository.dart) | Modified | Propagate underlying photo-upload failures so supported connection-loss edits can queue. |
| [lib/data/repositories/harvest_entry_repository.dart](../lib/data/repositories/harvest_entry_repository.dart) | Modified | Stable harvest/batch retry identities, local queue on connection loss, and safe rollback of confirmed new-write rejections. |
| [lib/data/repositories/loan_repository.dart](../lib/data/repositories/loan_repository.dart) | Modified | Allow previously loaded loan catalog data to open offline. |
| [lib/data/repositories/notification_repository.dart](../lib/data/repositories/notification_repository.dart) | Modified | Propagate failed notification writes so synchronization retains unsent actions. |
| [lib/data/repositories/settings_repository.dart](../lib/data/repositories/settings_repository.dart) | Modified | Remove unnecessary interpolation; retain preference persistence. |
| [lib/data/services/app_settings_service.dart](../lib/data/services/app_settings_service.dart) | Modified | Initialize localized date data and update the default date-format locale. |
| [lib/data/services/auth_service.dart](../lib/data/services/auth_service.dart) | Modified | Start pending synchronization after sign-in; preserve existing authentication changes. |
| [lib/data/services/connectivity_service.dart](../lib/data/services/connectivity_service.dart) | Modified | Actual reachability, offline recovery probes, and immediate recheck when the network changes during a shared probe. |
| [lib/data/services/hive_service.dart](../lib/data/services/hive_service.dart) | Modified | Stable retry IDs, one-time legacy queue-owner attribution, account-scoped loan caches, and queue change events. |
| [lib/data/services/market_types_service.dart](../lib/data/services/market_types_service.dart) | Modified | Localize the unassigned-market fallback; preserve database-defined market types and channels. |
| [lib/data/services/offline_action_replay.dart](../lib/data/services/offline_action_replay.dart) | Modified | Replay capital contributions with their persisted record IDs. |
| [lib/data/services/offline_actions.dart](../lib/data/services/offline_actions.dart) | Modified | Queue supported dropped-connection writes, recognize storage transport failures, guard the original account, and exclude Buyers. |
| [lib/data/services/offline_cache.dart](../lib/data/services/offline_cache.dart) | Modified | Role-aware encrypted snapshots, permission-error handling, account isolation, and original cache timestamps on fallback. |
| [lib/data/services/offline_read_client.dart](../lib/data/services/offline_read_client.dart) | Created | Account/role/schema/range-scoped REST and 24 read-only RPC snapshots; live status/Buyer exclusions and replay session guards. |
| [lib/data/services/profile_photo_service.dart](../lib/data/services/profile_photo_service.dart) | Modified | Optional propagation of original upload errors for queue-capable profile flows. |
| [lib/data/services/sync_service.dart](../lib/data/services/sync_service.dart) | Modified | Automatic/manual single-flight sync, account guards across awaits, ordered action replay, and retained failure reasons. |
| [lib/main.dart](../lib/main.dart) | Modified | Install the root connectivity overlay and start/resume automatic synchronization. |
| [lib/presentation/navigation/app_router.dart](../lib/presentation/navigation/app_router.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/admin/add_new_member_screen.dart](../lib/presentation/screens/admin/add_new_member_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_activity_screen.dart](../lib/presentation/screens/admin/admin_activity_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_calendar_screen.dart](../lib/presentation/screens/admin/admin_calendar_screen.dart) | Modified | Theme/localization updates and removal of an unused connectivity subscription. |
| [lib/presentation/screens/admin/admin_dashboard_screen.dart](../lib/presentation/screens/admin/admin_dashboard_screen.dart) | Modified | Related display/localization corrections, analyzer cleanup, and source formatting. |
| [lib/presentation/screens/admin/admin_edit_profile_screen.dart](../lib/presentation/screens/admin/admin_edit_profile_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_inventory_screen.dart](../lib/presentation/screens/admin/admin_inventory_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_notifications_screen.dart](../lib/presentation/screens/admin/admin_notifications_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_order_detail_screen.dart](../lib/presentation/screens/admin/admin_order_detail_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_profile_screen.dart](../lib/presentation/screens/admin/admin_profile_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_route_placeholder_screen.dart](../lib/presentation/screens/admin/admin_route_placeholder_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/admin_settings_screen.dart](../lib/presentation/screens/admin/admin_settings_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/all_listings_screen.dart](../lib/presentation/screens/admin/all_listings_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/analytics_dashboard_screen.dart](../lib/presentation/screens/admin/analytics_dashboard_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/assistance_requests_screen.dart](../lib/presentation/screens/admin/assistance_requests_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/balik_tangkilik_management_screen.dart](../lib/presentation/screens/admin/balik_tangkilik_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/broadcast_history_screen.dart](../lib/presentation/screens/admin/broadcast_history_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/buyer_details_screen.dart](../lib/presentation/screens/admin/buyer_details_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/buyer_management_screen.dart](../lib/presentation/screens/admin/buyer_management_screen.dart) | Modified | Related display/localization corrections, analyzer cleanup, and source formatting. |
| [lib/presentation/screens/admin/buyer_order_history_screen.dart](../lib/presentation/screens/admin/buyer_order_history_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/cooperative_stock_report_screen.dart](../lib/presentation/screens/admin/cooperative_stock_report_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/create_officer_account_screen.dart](../lib/presentation/screens/admin/create_officer_account_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/crop_management_screen.dart](../lib/presentation/screens/admin/crop_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/crop_request_approval_screen.dart](../lib/presentation/screens/admin/crop_request_approval_screen.dart) | Modified | Correct asynchronous context guards and localize missing names/category display without changing data keys. |
| [lib/presentation/screens/admin/delivery_settings_screen.dart](../lib/presentation/screens/admin/delivery_settings_screen.dart) | Modified | Use the current Switch thumb-color API; preserve delivery behavior. |
| [lib/presentation/screens/admin/expense_report_screen.dart](../lib/presentation/screens/admin/expense_report_screen.dart) | Modified | Related display/localization corrections, analyzer cleanup, and source formatting. |
| [lib/presentation/screens/admin/export_center_screen.dart](../lib/presentation/screens/admin/export_center_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/farmer_details_screen.dart](../lib/presentation/screens/admin/farmer_details_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/farmer_harvest_history_screen.dart](../lib/presentation/screens/admin/farmer_harvest_history_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/farmer_management_screen.dart](../lib/presentation/screens/admin/farmer_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/issue_new_loan_screen.dart](../lib/presentation/screens/admin/issue_new_loan_screen.dart) | Modified | Queue loan submissions offline with one stable request ID and defer server validation/reference numbers. |
| [lib/presentation/screens/admin/listing_edit_request_screen.dart](../lib/presentation/screens/admin/listing_edit_request_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/listing_review_screen.dart](../lib/presentation/screens/admin/listing_review_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/loan_dashboard_screen.dart](../lib/presentation/screens/admin/loan_dashboard_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/loan_details_screen.dart](../lib/presentation/screens/admin/loan_details_screen.dart) | Modified | Remove the early offline block and display previously loaded loan details. |
| [lib/presentation/screens/admin/loan_history_screen.dart](../lib/presentation/screens/admin/loan_history_screen.dart) | Modified | Cached loan-history reads and removal of an unused connectivity subscription. |
| [lib/presentation/screens/admin/loan_item_management_screen.dart](../lib/presentation/screens/admin/loan_item_management_screen.dart) | Modified | Theme/category-label updates and removal of an unused connectivity subscription. |
| [lib/presentation/screens/admin/loan_requests_screen.dart](../lib/presentation/screens/admin/loan_requests_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/market_linking_screen.dart](../lib/presentation/screens/admin/market_linking_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/member_contribution_report_screen.dart](../lib/presentation/screens/admin/member_contribution_report_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/notification_broadcast_screen.dart](../lib/presentation/screens/admin/notification_broadcast_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/order_delivery_map_screen.dart](../lib/presentation/screens/admin/order_delivery_map_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/order_management_screen.dart](../lib/presentation/screens/admin/order_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/pending_approvals_screen.dart](../lib/presentation/screens/admin/pending_approvals_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/price_management_screen.dart](../lib/presentation/screens/admin/price_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/program_enrollment_requests_screen.dart](../lib/presentation/screens/admin/program_enrollment_requests_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/program_management_screen.dart](../lib/presentation/screens/admin/program_management_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/program_outcome_detail_screen.dart](../lib/presentation/screens/admin/program_outcome_detail_screen.dart) | Modified | Theme-aware image placeholders and analyzer import cleanup. |
| [lib/presentation/screens/admin/program_outcomes_screen.dart](../lib/presentation/screens/admin/program_outcomes_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/program_products_screen.dart](../lib/presentation/screens/admin/program_products_screen.dart) | Modified | Current Switch API, consistent control-flow blocks, and formatting. |
| [lib/presentation/screens/admin/record_payment_screen.dart](../lib/presentation/screens/admin/record_payment_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/sales_report_screen.dart](../lib/presentation/screens/admin/sales_report_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/admin/staff_accountability_screen.dart](../lib/presentation/screens/admin/staff_accountability_screen.dart) | Modified | Management/Officer theme and localization consistency, data-key preservation, and source formatting. |
| [lib/presentation/screens/auth/force_password_change_screen.dart](../lib/presentation/screens/auth/force_password_change_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/auth/login_screen.dart](../lib/presentation/screens/auth/login_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/auth/register_screen.dart](../lib/presentation/screens/auth/register_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/auth/reset_password_screen.dart](../lib/presentation/screens/auth/reset_password_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/auth/welcome_screen.dart](../lib/presentation/screens/auth/welcome_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/buyer/add_edit_address_screen.dart](../lib/presentation/screens/buyer/add_edit_address_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/buyer_account_screen.dart](../lib/presentation/screens/buyer/buyer_account_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/buyer_edit_profile_screen.dart](../lib/presentation/screens/buyer/buyer_edit_profile_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/buyer_notifications_screen.dart](../lib/presentation/screens/buyer/buyer_notifications_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/buyer_recent_activity_screen.dart](../lib/presentation/screens/buyer/buyer_recent_activity_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/buyer_settings_screen.dart](../lib/presentation/screens/buyer/buyer_settings_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/cart_checkout_result_screen.dart](../lib/presentation/screens/buyer/cart_checkout_result_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/cart_screen.dart](../lib/presentation/screens/buyer/cart_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/checkout_screen.dart](../lib/presentation/screens/buyer/checkout_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/listing_details_screen.dart](../lib/presentation/screens/buyer/listing_details_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/marketplace_browse_screen.dart](../lib/presentation/screens/buyer/marketplace_browse_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/my_addresses_screen.dart](../lib/presentation/screens/buyer/my_addresses_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/my_orders_screen.dart](../lib/presentation/screens/buyer/my_orders_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/order_detail_screen.dart](../lib/presentation/screens/buyer/order_detail_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/order_success_screen.dart](../lib/presentation/screens/buyer/order_success_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/buyer/price_monitoring_screen.dart](../lib/presentation/screens/buyer/price_monitoring_screen.dart) | Modified | Buyer theme/localization consistency and display-label preservation; source formatting. |
| [lib/presentation/screens/farmer/browse_programs_screen.dart](../lib/presentation/screens/farmer/browse_programs_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/cooperative_product_details_screen.dart](../lib/presentation/screens/farmer/cooperative_product_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/create_listing_screen.dart](../lib/presentation/screens/farmer/create_listing_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/crop_details_screen.dart](../lib/presentation/screens/farmer/crop_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/crop_listing_screen.dart](../lib/presentation/screens/farmer/crop_listing_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/edit_farm_details_screen.dart](../lib/presentation/screens/farmer/edit_farm_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/edit_listing_screen.dart](../lib/presentation/screens/farmer/edit_listing_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farm_location_full_map_screen.dart](../lib/presentation/screens/farmer/farm_location_full_map_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_analytics_screen.dart](../lib/presentation/screens/farmer/farmer_analytics_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_dashboard_screen.dart](../lib/presentation/screens/farmer/farmer_dashboard_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_edit_profile_screen.dart](../lib/presentation/screens/farmer/farmer_edit_profile_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_listing_detail_screen.dart](../lib/presentation/screens/farmer/farmer_listing_detail_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_marketplace_tab.dart](../lib/presentation/screens/farmer/farmer_marketplace_tab.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_notifications_screen.dart](../lib/presentation/screens/farmer/farmer_notifications_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_orders_screen.dart](../lib/presentation/screens/farmer/farmer_orders_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_profile_screen.dart](../lib/presentation/screens/farmer/farmer_profile_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_recent_activity_screen.dart](../lib/presentation/screens/farmer/farmer_recent_activity_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_settings_screen.dart](../lib/presentation/screens/farmer/farmer_settings_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/farmer_transaction_history_screen.dart](../lib/presentation/screens/farmer/farmer_transaction_history_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/harvest_entry_form_screen.dart](../lib/presentation/screens/farmer/harvest_entry_form_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/harvest_history_screen.dart](../lib/presentation/screens/farmer/harvest_history_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/harvest_hub_screen.dart](../lib/presentation/screens/farmer/harvest_hub_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/listing_success_screen.dart](../lib/presentation/screens/farmer/listing_success_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/manage_inventory_screen.dart](../lib/presentation/screens/farmer/manage_inventory_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/market_rate_details_screen.dart](../lib/presentation/screens/farmer/market_rate_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_contribution_screen.dart](../lib/presentation/screens/farmer/my_contribution_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_expenses_screen.dart](../lib/presentation/screens/farmer/my_expenses_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_listings_screen.dart](../lib/presentation/screens/farmer/my_listings_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_loan_history_screen.dart](../lib/presentation/screens/farmer/my_loan_history_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_loan_requests_screen.dart](../lib/presentation/screens/farmer/my_loan_requests_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_loans_screen.dart](../lib/presentation/screens/farmer/my_loans_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_market_linking_screen.dart](../lib/presentation/screens/farmer/my_market_linking_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_payment_history_screen.dart](../lib/presentation/screens/farmer/my_payment_history_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/my_programs_screen.dart](../lib/presentation/screens/farmer/my_programs_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/pending_applicant_screen.dart](../lib/presentation/screens/farmer/pending_applicant_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/pending_review_details_screen.dart](../lib/presentation/screens/farmer/pending_review_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/program_details_screen.dart](../lib/presentation/screens/farmer/program_details_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/received_items_screen.dart](../lib/presentation/screens/farmer/received_items_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/report_outcome_screen.dart](../lib/presentation/screens/farmer/report_outcome_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/request_assistance_screen.dart](../lib/presentation/screens/farmer/request_assistance_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/request_loan_screen.dart](../lib/presentation/screens/farmer/request_loan_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/select_crop_screen.dart](../lib/presentation/screens/farmer/select_crop_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/farmer/view_market_screen.dart](../lib/presentation/screens/farmer/view_market_screen.dart) | Modified | Farmer theme/localization consistency and applicable offline UI updates; source formatting. |
| [lib/presentation/screens/shared/about_sagana_screen.dart](../lib/presentation/screens/shared/about_sagana_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/shared/coop_offer_negotiation_screen.dart](../lib/presentation/screens/shared/coop_offer_negotiation_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/shared/guest_screens.dart](../lib/presentation/screens/shared/guest_screens.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/shared/listing_history_screen.dart](../lib/presentation/screens/shared/listing_history_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/screens/splash_screen.dart](../lib/presentation/screens/splash_screen.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/shell/role_drawers.dart](../lib/presentation/shell/role_drawers.dart) | Modified | Related theme/localization integration and source formatting. |
| [lib/presentation/widgets/account_card.dart](../lib/presentation/widgets/account_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/address_map_widgets.dart](../lib/presentation/widgets/address_map_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/admin_top_bar.dart](../lib/presentation/widgets/admin_top_bar.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/app_dropdown_field.dart](../lib/presentation/widgets/app_dropdown_field.dart) | Modified | Resolve the localized prompt default at runtime; remove the invalid constant default/context reference. |
| [lib/presentation/widgets/app_navigation_drawer.dart](../lib/presentation/widgets/app_navigation_drawer.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/auth_visuals.dart](../lib/presentation/widgets/auth_visuals.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/buyer_top_bar.dart](../lib/presentation/widgets/buyer_top_bar.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/cached_data_notice.dart](../lib/presentation/widgets/cached_data_notice.dart) | Modified | Avoid inserting an offline connection banner into page layout. |
| [lib/presentation/widgets/connectivity_overlay.dart](../lib/presentation/widgets/connectivity_overlay.dart) | Created | Floating, localized, theme-aware lost/restored connection notice above all pages. |
| [lib/presentation/widgets/contact_email_verification.dart](../lib/presentation/widgets/contact_email_verification.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/coop_offer_widgets.dart](../lib/presentation/widgets/coop_offer_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/cooperative_inventory_history.dart](../lib/presentation/widgets/cooperative_inventory_history.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/crop_catalog_sheet.dart](../lib/presentation/widgets/crop_catalog_sheet.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/crop_category_chips.dart](../lib/presentation/widgets/crop_category_chips.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/crop_photo_capture.dart](../lib/presentation/widgets/crop_photo_capture.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/disposal_action_sheet.dart](../lib/presentation/widgets/disposal_action_sheet.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/edit_crop_sheet.dart](../lib/presentation/widgets/edit_crop_sheet.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/farmer_loan_widgets.dart](../lib/presentation/widgets/farmer_loan_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/farmer_top_bar.dart](../lib/presentation/widgets/farmer_top_bar.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/filter_icon_button.dart](../lib/presentation/widgets/filter_icon_button.dart) | Modified | Localize the default accessibility label at build time. |
| [lib/presentation/widgets/fixed_farmer_address_fields.dart](../lib/presentation/widgets/fixed_farmer_address_fields.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/fulfillment_info_card.dart](../lib/presentation/widgets/fulfillment_info_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/guest_navigation_drawer.dart](../lib/presentation/widgets/guest_navigation_drawer.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/guest_prompt.dart](../lib/presentation/widgets/guest_prompt.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/harvest_log_widgets.dart](../lib/presentation/widgets/harvest_log_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/listing_history_widgets.dart](../lib/presentation/widgets/listing_history_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/loan_request_widgets.dart](../lib/presentation/widgets/loan_request_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/map_attribution_links.dart](../lib/presentation/widgets/map_attribution_links.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/market_linking_sale_widgets.dart](../lib/presentation/widgets/market_linking_sale_widgets.dart) | Modified | Use locale-aware month/day formatting. |
| [lib/presentation/widgets/member_patronage_card.dart](../lib/presentation/widgets/member_patronage_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/notification_day_groups.dart](../lib/presentation/widgets/notification_day_groups.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/notification_ui.dart](../lib/presentation/widgets/notification_ui.dart) | Modified | Localized system notification rendering and theme-aware neutral/green/error icons. |
| [lib/presentation/widgets/order_payment_widgets.dart](../lib/presentation/widgets/order_payment_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/order_result_pieces.dart](../lib/presentation/widgets/order_result_pieces.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/pending_applicant_views.dart](../lib/presentation/widgets/pending_applicant_views.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/person_name_fields.dart](../lib/presentation/widgets/person_name_fields.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/planting_forecast_card.dart](../lib/presentation/widgets/planting_forecast_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/price_display_widgets.dart](../lib/presentation/widgets/price_display_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/product_buy_now_sheet.dart](../lib/presentation/widgets/product_buy_now_sheet.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/product_card.dart](../lib/presentation/widgets/product_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/program_history_sheet.dart](../lib/presentation/widgets/program_history_sheet.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/program_member_details.dart](../lib/presentation/widgets/program_member_details.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/program_return_panel.dart](../lib/presentation/widgets/program_return_panel.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/psgc_address_fields.dart](../lib/presentation/widgets/psgc_address_fields.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/quantity_stepper.dart](../lib/presentation/widgets/quantity_stepper.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/quantity_unit_field.dart](../lib/presentation/widgets/quantity_unit_field.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/recent_activity_widgets.dart](../lib/presentation/widgets/recent_activity_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/report_summary_widgets.dart](../lib/presentation/widgets/report_summary_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/request_card.dart](../lib/presentation/widgets/request_card.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/sagana_logo_mark.dart](../lib/presentation/widgets/sagana_logo_mark.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/set_password_form.dart](../lib/presentation/widgets/set_password_form.dart) | Modified | Localize default heading, body, and submit label at build time. |
| [lib/presentation/widgets/shared_widgets.dart](../lib/presentation/widgets/shared_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/staff_access_matrix.dart](../lib/presentation/widgets/staff_access_matrix.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/stock_widgets.dart](../lib/presentation/widgets/stock_widgets.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/sync_status_card.dart](../lib/presentation/widgets/sync_status_card.dart) | Modified | Keep Sync Now, reflect automatic sync, and localize failed-record explanations. |
| [lib/presentation/widgets/temp_password_dialog.dart](../lib/presentation/widgets/temp_password_dialog.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/presentation/widgets/top_harvested_crops_chart.dart](../lib/presentation/widgets/top_harvested_crops_chart.dart) | Modified | Shared widget theme/localization consistency and source formatting. |
| [lib/supabase_options.dart](../lib/supabase_options.dart) | Modified | Attach the shared offline read client to Supabase. |
| [pubspec.lock](../pubspec.lock) | Modified | Record resolved dependency metadata and direct dependencies; retain existing dependency changes. |
| [pubspec.yaml](../pubspec.yaml) | Modified | Declare direct http and Flutter SDK flutter_web_plugins dependencies; retain existing Firebase/share_plus changes. |
| [test/change_email_test.dart](../test/change_email_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/contact_email_verification_test.dart](../test/contact_email_verification_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/dropdown_button_overflow_test.dart](../test/dropdown_button_overflow_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/market_linking_followups_test.dart](../test/market_linking_followups_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/member_profile_cards_test.dart](../test/member_profile_cards_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/members_controls_test.dart](../test/members_controls_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/notification_read_status_test.dart](../test/notification_read_status_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/officer_code_verification_test.dart](../test/officer_code_verification_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/order_reference_test.dart](../test/order_reference_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/pending_applicant_views_test.dart](../test/pending_applicant_views_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/planting_forecast_card_test.dart](../test/planting_forecast_card_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/quantity_stepper_test.dart](../test/quantity_stepper_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/reports_product_sales_test.dart](../test/reports_product_sales_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
| [test/unified_ui_revision_test.dart](../test/unified_ui_revision_test.dart) | Modified | Analyzer-only const/block/constructor/interpolation cleanup and formatting; existing assertions/edits retained; not executed. |
