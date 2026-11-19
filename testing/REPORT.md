# SAGANA Software Testing: Final Report

Run 2026-11-18 to 2026-11-19 on branch `testing/software-testing`. Everything ran against a local Docker copy of the database (`http://127.0.0.1:54321`). The live Supabase project was never touched. Evidence for every line is in `testing/results/`. Nothing is committed.

| Testing Category | Status |
|---|---|
| Functional Testing | Done |
| Non-Functional Testing | Done |

## 1. Results by test type

| Type | Result | Evidence |
|---|---|---|
| Regression | 2,667 of 2,667 Dart tests pass (baseline 174 failing; the 35 stale tests left at the first report were rewritten). SQL harness 322/322. | `dart_tests_final4.json` |
| White-box | Function permissions, row-level security, storage policies, stock and money rules and the sync replay code reviewed. Replay is safe: queued expenses carry a client id (second send refused), loans and payments carry idempotency keys. | `[replay]` checks in `api2_run2.txt`; lockdown scripts |
| API | 310 of 310 checks pass: part 1 141 (auth, isolation, escalation, Officer gate, marketplace, orders, loans, restrictions, 20 simultaneous orders), part 2 133 (cooperative stock, programs, distribution, outcomes, returns, cooperative offers, market linking, delivery, notifications, broadcasts, replay), storage 36. | `api_run6.txt`, `api2_run2.txt`, `storage_run2.txt` |
| Smoke | Six roles, 6 browser configurations, every main tab: no error text, console error or failed request. | `e2e_run_*.txt` |
| Black-box | 24 + 19 scenario checks pass (sign-in cases, Farmer expense boundaries incl. Tagalog and 300 characters, Buyer search, quantity limit and order, Manager and Officer approvals, View Only vs Manage, member approval, each confirmed in the database). | `e2e_flows.txt`, `e2e_blackbox.txt` |
| Ad-hoc / Exploratory | Time-boxed session (triple taps, Back, resizing, 60 tab switches): 9 of 9 pass. Free exploration found B5, B6, B7, B13. | `e2e_adhoc.txt` |
| Recovery | 21 checks pass: offline writes kept and sent once; restart with a waiting write; database stopped during a save (form keeps its data, saves once after restart); Docker restart; corrupted token. | `e2e_recovery2.txt`, `e2e_flows.txt` |
| Performance / Load / Stress | See section 3. | `perf_results.json`, `perf_ui_run*.txt` |
| Security | 18 extra checks pass (password rules, token tampering, account enumeration, sign-in lockout) plus the 310 API checks. 189 packages checked against the public OSV advisory database: none with advisories. No service-role key or keystore is committed. | `security_extra_results.json`, `dependency_audit.json` |
| Compatibility | 320 to 1280 px, light and dark, English and Tagalog, all roles; text size 100% to 200% on Farmer, Buyer, Manager and Officer screens. | `e2e_run_*.txt`, `e2e_textscale.txt`, `shots/ts*` |
| Usability | Heuristic review: section 5. | `e2e_tapsize.txt`, `shots/` |

## 2. Bugs found and how each was fixed

| # | Problem | Cause | Fix |
|---|---|---|---|
| B1 | Anyone, even signed out, could put a notification in any inbox, change any farmer's stock, and run the scheduled jobs. | 10 helper functions were executable by everyone. | `supabase_schema_security_01_lockdown.sql` |
| B2 | Any signed-in user could read every farmer's available stock batches. | Policy checked only `status = available`. | Same script: only batches of approved listings are readable. |
| B3 | Public photo buckets accepted HTML and scripts. | No file-type list. | Same script: images (and generic binary) only. |
| B4 | Capital Share wording said "enrolled" instead of "joined the Product Sales program". | Wording slip. | English and Tagalog text corrected. |
| B5 | With about 200 or more listings the Marketplace failed to load and listing details never opened (a 45 KB request address was refused). | "id in this long list" queries. | `lib/core/utils/chunked_in.dart` sends long lists in slices of 80; applied in 18 repository files. Test `chunked_in_test.dart`. |
| B6 | Tagalog Manager dashboard kept English sentences after the language was switched. | Sentences are written when data is fetched. | Dashboard reloads on a language change. |
| B7 | Manager Order Management showed only the newest 1,000 orders: chips read "All (1000)" of 6,963, and the oldest, longest-waiting pending orders could not be seen or approved. The same limit applied to All Listings and cooperative orders. | The database returns at most 1,000 rows per query. | `lib/core/utils/fetch_all_rows.dart` reads page after page (three at a time); used by the three lists. Test `fetch_all_rows_test.dart`. Verified in Chrome: All (6963). |
| B8 | A market-linking request could be saved for 0, negative or oversized kg when the API was called directly. | Policy checked only ownership. | `supabase_schema_security_02_input_validation.sql` (trigger). |
| B9 | A signed-in user could rewrite the text and screen link of their own notification. | Policy allowed any column. | Same script: only the read status can be changed. |
| B10 | A broadcast with a blank title or message was delivered as an empty notification. | No check. | Same script: blank title or message refused. |
| B11 | Unlimited wrong passwords were accepted for an account (60 in a row, no slow-down). | The sign-in service does not limit failed passwords. | `supabase_schema_security_03_signin_lockout.sql`: 10 wrong passwords in 15 minutes lock the account (even the right password is refused) until the window ends; a right password earlier clears the count. The app shows the friendly "Too many attempts" text (`auth_service.dart`, test `signin_lockout_message_test.dart`). |
| B12 | The server accepted 6- and 7-character passwords while the app requires 8. | Authentication setting was the default (6). | Set locally to 8 and verified. **Must be changed on the live project** (see section 7). |
| B13 | At enlarged text size: Manager Loans numbers shrank to a few pixels while labels stayed large and the two action buttons were cut ("Issue Ne..."); status chip rows were clipped; the Farmer "Marketplace / Listing" switch broke a word in two. | Fixed-size boxes. | Cards, chip rows and the switch now grow or shrink with the text; the buttons stack. Test `text_scale_layout_fixes_test.dart`. Verified in Chrome at 150%. |

Other work: about 140 stale Dart tests were corrected, and the last 35 (source-text tests) were rewritten to match intended behaviour (for example the later per-item Capital Share loan limit replaced the old minimum-capital rule). Four API checks that assumed an empty database were made independent of seed data.

## 3. Performance, load and stress

Test laptop (7.7 GB RAM shared with Docker); 160 users, 1,501 listings, about 7,000 orders, 301 loans.

| Phase | Users | Requests/s | Errors | p50 | p95 | p99 |
|---|---|---|---|---|---|---|
| Baseline | 1 | 52 | 0% | 17 ms | 62 ms | 77 ms |
| Normal | 25 | 109 | 0% | 16 ms | 91 ms | 145 ms |
| Heavy | 50 | 160 | 0% | 133 ms | 623 ms | 958 ms |
| Stress | 100 | 162 | 0% | 438 ms | 1.7 s | 2.8 s |
| Stress | 200 | 137 | 0.24% | 1.0 s | 4.0 s | 6.1 s |
| Stress | 400 | 486 | 84% | 2.4 s | 8.0 s | 9.9 s |
| Recovery | 1 | 57 | 0% | 9 ms | 133 ms | 144 ms |

- No slow query: the slowest database queries take 2 ms and 12 ms. Slowdown is uniform and comes from the gateway and the shared laptop.
- Breaking point is between 200 and 400 simultaneous users here; it fails by refusing connections, with no corrupt data, and recovers fully.
- Screen load times in Chrome (median of 3 runs, at this volume): Farmer tabs 0.2 to 2.3 s; Buyer Browse, Orders and Prices under 0.4 s; Manager Loans 0.6 to 1.2 s, Members 2 to 3 s, Order Management about 2.3 s before the B7 fix (it now loads every order, about 9 s for 7,000 orders). **Slower than the 3-second target at this volume:** Manager Dashboard when first opened (9 to 12 s), Reports tab (7 to 9 s), Harvest Report (about 11 s), Sales Report (about 4 s). The cause is many small requests (55 on the Reports tab) queued behind the browser's connection limit and client-side totalling, not slow queries. A real cooperative has far less data; these are the screens to watch as data grows (a server-side summary would fix them).

## 4. Not fixed, for your decision

- If the server is down and a screen was never opened before, it shows an empty list with no "could not load" message. With a saved copy it shows the saved list (tested).
- A corrupted or expired sign-in token shows the "You're Offline" notice instead of signing out cleanly (no crash).
- Sign-in address limit: the authentication service does not slow down repeated attempts from one address; the account lockout (B11) covers guessing at one account.
- Tap targets under the 48 px guideline: header icon buttons (38 px) and text links such as "Forgot Password?", "View Market", "View All" (17 to 19 px tall).
- On the web build the layout stretches to the full window on wide screens (not relevant to mobile devices).
- Other lists that read a plain query may also stop at 1,000 rows once data grows; only the three confirmed ones (orders, listings, cooperative orders) were changed.
- `test_rpc.bat` and `test_rpc.ps1` in the project root hold the live project address and the public key (not secret, but look like leftovers).
- Dependencies are many versions behind (no advisories found today).
- Four files were changed by someone else while testing (`farmer_edit_profile_screen.dart`, `my_expenses_screen.dart`, `planting_forecast_card.dart`, `top_harvested_crops_chart.dart`, plus `test/inline_errors_and_unit_note_test.dart`). They are not part of this testing and were not touched.

## 5. Usability review (heuristic; no real users)

Good: clear titles; the same bottom navigation per role; price and stock visible on every listing card; plain sign-in errors that do not reveal whether a username exists; "Failed to save. Please try again." keeps what was typed; "You have view-only access to this module." for View Only; offline and back-online notices; Tagalog and dark mode applied across roles. Task lengths (taps from the home screen): Farmer add expense 4; Farmer see market prices 1; Buyer buy a crop 4; Manager approve an order 5; Manager approve a member 4 (plus search); a View Only Officer gets the refusal after 1 tap. Weak: the four items in section 4 about tap-target size and missing "could not load" message; the language and theme switches are only in the side menu opened from the logo, which a new user may not find; at 200% text some labels end in "..." (bottom navigation, cards).

## 6. Not covered and why

- A physical mobile device: none available. Camera capture, push notifications and device-only behaviour were tested through their server side only.
- Edge (not installed), Firefox and Safari: only Chrome was used.
- The Manager program-creation form was exercised in the API and in a widget test; the on-screen "Distribute from" list was opened in Chrome and works.
- An address-level sign-in rate limit (section 4).

## 7. What you need to do on the live project

1. Run in the Supabase SQL Editor, in order: `supabase_schema_security_01_lockdown.sql` (you said this one is already run), `supabase_schema_security_02_input_validation.sql`, `supabase_schema_security_03_signin_lockout.sql`.
2. Turn on the sign-in lockout: Dashboard, Authentication, Hooks, "Password Verification Attempt", choose the Postgres function `public.hook_password_verification_attempt`. If your plan does not offer this hook, turn on CAPTCHA under Authentication, Attack Protection instead.
3. Authentication, Sign In / Providers, Password: set the minimum password length to 8.
4. Review and commit the code changes (B4 to B7, B11, B13: `chunked_in.dart`, `fetch_all_rows.dart`, the repositories, the screens, the new tests) and the `testing/` folder.

## 8. Incident during testing

On 2026-11-18 the whole `test/` folder disappeared from disk during the first full Dart run. The cause was not found. It was restored with `git checkout -- test` and the fixes were re-applied; a copy is at `C:\Users\Administrator\sagana-test-backup\test_fixed`. Later full runs left it intact. If it happens again, check antivirus or sync software.
