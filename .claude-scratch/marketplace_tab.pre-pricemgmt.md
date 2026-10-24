# SAGANA Admin Marketplace — Final System Analysis & Documentation

**Scope:** Admin → Marketplace tab and every workflow, table, RPC, RLS policy, and cross-module dependency that affects it.
**Nature of this document:** Understanding and validation only. No code, SQL, or implementation proposals are contained here except where explicitly labeled as historical context from work already completed and verified in this project.

---

## File Verification Note

This documentation draws on the complete Marketplace/Order/Cooperative-Offer/Market-Linking SQL and RPC set, all 8 Marketplace repositories, all 9 Admin Marketplace screens (`offer_detail_screen.dart` added in a later engagement — see §6), the relevant models, `app_router.dart`/`app_routes.dart`, `admin_bottom_nav.dart`, `information.md`, `SAGANA_System_Documentation.md`, `admin_reports_repository.dart`, `analytics_repository.dart`, `balik_tangkilik_repository.dart`, `contribution_repository.dart`, and `member_sales_aggregation.dart` — all read directly, not inferred from filenames.

**One disclosed gap, partially closed in a later engagement:** the Farmer-side and Buyer-side *screens* (e.g. `create_listing_screen.dart`, farmer's Market Linking enrollment view, `marketplace_browse_screen.dart`, `cart_screen.dart`) were never provided at the time this note was first written. Every repository those screens call **was** reviewed in full, which is what determines actual data flow, validation, and database state — so every business rule and state transition below is defended with full confidence. A later engagement did directly read `create_listing_screen.dart`, `my_market_linking_screen.dart`, and `disposal_action_sheet.dart` (see §7, §15, and `farmer/listing_tab.md`'s own documentation) — those three are no longer part of the gap. `marketplace_browse_screen.dart`/`cart_screen.dart` and the rest of the Buyer-side screens remain undocumented here at the exact visual/interaction level; see the separate Buyer documentation set for that.

---

# 1. Marketplace Module Scope

The Admin Marketplace tab (`/admin/marketplace*`, `/admin/listings*`) governs four **structurally independent** workflows that share one underlying resource — a farmer's harvested, batched inventory:

1. **Marketplace Listings & Orders** — open-market: farmer lists, any buyer orders. Ginger is excluded from this path entirely — see §2–3.
2. **Cooperative Purchase Offers** — the cooperative itself is the buyer. **Widened in a later engagement, then given full financial parity in the Admin-Reports tab pass that followed:** any crop except Ginger is now offerable, and every confirmed offer — any crop — records a real Balik-Tangkilik-eligible transaction. There is no longer a Palay/Peanut-only settlement split; see §6.
3. **Market Linking / DA-AMAD Pipeline** — the cooperative brokers a connection to an external buyer without itself transacting. Ginger's *only* disposal path, enforced by the crop's exclusive selling channel (`crop_master.exclusive_channel = 'da_amad_market_linking'`, set in the database only) rather than merely by convention — see §7.
4. Everything downstream that consumes the above: the Marketplace Dashboard, Sales/Operational Reports, Analytics.

**Verified NOT part of Marketplace**, despite name proximity:
- **Admin Inventory** (`admin_inventory_screen.dart`) is a separate module. Marketplace only *reads and reserves against* `inventory_batches`; it does not own that table's creation or harvest-side lifecycle — Harvest does.
- **Balik-Tangkilik** is a separate module with its own repository and its own year-end computation logic. It *consumes* Marketplace/Cooperative-Offer data but does not live inside Marketplace.

---

# 2–3. Marketplace Listings — Complete Lifecycle

**Purpose within SAGANA:** gives a farmer a channel to sell produce directly to any buyer, at a farmer-set price, without the cooperative acting as intermediary. **Corrected in a later engagement:** Ginger is no longer part of this crop set. Ginger's crop carries `crop_master.exclusive_channel = 'da_amad_market_linking'` (a selling channel, not a market type) and is rejected server-side by `create_listing_with_reservation` (`supabase_schema_create_listing_ginger_guard.sql`) — its only disposal path is Market Linking (§7). The farmer-facing crop set sellable through this Marketplace path is now every active `crop_master` row *except* Ginger.
**Owned by:** Farmer (creates, withdraws, resubmits, deletes). **Moderated by:** Admin (approves/rejects/requests changes). **Consumed by:** Buyer (orders against it once live).

### State machine

| State | Meaning | Who triggers it | Inventory effect | Buyer-visible? | Reversible? |
|---|---|---|---|---|---|
| `pending_review` | Newly created, awaiting admin decision | Farmer (create) | **Full listed quantity reserved immediately** — `available_kg` drops at creation, not at approval | No | Yes (withdraw) |
| `approved` | Admin-cleared, live on the Marketplace | Admin | None — reservation already happened at creation | Yes | Yes (withdraw) |
| `rejected` | Admin declined | Admin | Reservation released, `available_kg` restored | No | No (terminal, but deletable) |
| `withdrawn` | Farmer cancelled their own listing | Farmer | Reservation released | No | No (terminal, but deletable) |
| `sold` | `remaining_kg` hit zero via buyer orders | System (via `place_order`) | No batch effect — only the listing's own `remaining_kg` moved | No | Yes, if an order against it is later cancelled |

**`changes_required` removed entirely in a later engagement.** This state, its RPC (`request_listing_changes`), and the resubmission RPC (`resubmit_listing_with_reservation`) all existed in an earlier version of this document — all three are now gone, confirmed absent via a direct `pg_proc` query after the removal migration (`supabase_schema_remove_changes_required.sql`, which also converted any listing rows still in that status to `rejected`, releasing their reservation and notifying the affected farmer). The review decision is now strictly binary: **Approve** or **Reject**. Listing Review's action footer went from three buttons (Request Changes / Approve / Reject) to two (Approve Listing / Reject Submission), styled to match the farmer's own Submission Success screen.

### The one fact to be able to defend without hesitation

**The full listed quantity is reserved against the batch at the moment of creation — not at approval, not at sale.** `create_listing_with_reservation` calls `_apply_batch_reservation`, decrementing `inventory_batches.available_kg` before any admin has even seen the listing. This exists specifically so that two listings (or a listing and a cooperative offer) cannot simultaneously claim the same physical stock while the first is merely awaiting review.

### Why Listing state, Inventory state, and Order state are deliberately separate concepts

A batch's `available_kg` reflects **commitment**, not sale — it drops the instant a listing, offer, or market-linking completion claims the stock, whether or not a buyer ever appears. A listing's own `remaining_kg` reflects **how much of that committed amount is still unsold to a specific buyer** — it exists only once the listing is created, and moves only when orders are placed or cancelled against *that listing*, never touching the batch directly. An order's status reflects **one buyer's individual transaction**, and only `complete_order` finally moves the batch's `sold_kg` — the single point across the entire pipeline where a batch is marked irreversibly sold. Collapsing these into one number would make it impossible to distinguish "committed but unsold" from "sold to a buyer but not yet fulfilled" from "physically gone" — three states a real cooperative genuinely needs kept apart (a listing can be withdrawn and its stock freed; an order can be cancelled and its portion of the listing freed; `complete_order` alone is final).

---

# 4. Inventory and Reservation Integrity

### The four columns, and what actually maintains each one

| Column | Meaning | What moves it |
|---|---|---|
| `quantity_kg` | Original logged harvest amount | Nothing in Marketplace/Orders/Offers/Market-Linking ever changes this |
| `available_kg` | Currently uncommitted stock | **Down:** `_apply_batch_reservation` (listing creation, cooperative offer creation, market-linking completion with a batch attached). **Up:** `_release_batch_reservation` (listing rejection/withdrawal, cooperative offer decline, order cancellation) |
| `sold_kg` | Irrevocably sold | Only at final settlement: `complete_order`, `complete_market_linking`. **Correction, verified directly against the live function body:** `confirm_cooperative_offer` does **not** touch `sold_kg` — true both before and after the Admin-Reports tab pass that gave it full financial parity (§6). A confirmed cooperative offer, for any crop, settles its `member_sales_transactions` row (a single settlement path now — see §6), but the source batch's `available_kg` stays at whatever `_apply_batch_reservation` committed at offer-creation time — permanently, since nothing ever releases or converts it to `sold_kg` for this path. |
| `reserved_kg` | — | **Dead schema.** Column exists, defaults to 0, confirmed via direct code inspection that no currently-live function writes to it. Only ever maintained by two now-superseded files (`buyer_orders.sql`, `order_management.sql`) from an earlier, deliberately-replaced "batch-centric" architecture. |

### The current live model does not track "reserved" as its own number

It's entirely implicit: `reserved_elsewhere = quantity_kg − available_kg − sold_kg`. This is not an oversight — it's the actual, current design (the reservation model deliberately moved away from a persistent `reserved_kg` counter). It became directly load-bearing during this project's own corrective history: a manual quantity-correction feature was first "fixed" against the wrong ceiling (`quantity_kg − sold_kg`), which still permitted a farmer to silently reopen already-committed stock. The correct rule, reached by working out the implicit relationship above, is that a manual correction can only ever **decrease** `available_kg`, never increase it — because every legitimate increase already happens automatically the moment a reservation is properly released. This is honest history worth being able to explain if asked, not a hidden embarrassment: the first attempt at the fix was itself caught and corrected during a subsequent verification pass, exactly as the process is supposed to work.

### What Marketplace explicitly does NOT do, with the reasoning

- **Creating a listing is not a sale.** Commitment moves (`available_kg`), revenue does not (`sold_kg` untouched) — a `pending_review` listing later rejected leaves zero trace on `sold_kg`.
- **A reservation is not an order.** The reservation happens once, for the full quantity, at listing creation, against the *batch*. An order happens per buyer, against the *listing's own* `remaining_kg`, potentially many times per listing.
- **An order is not "just another listing."** Confirmed structurally separate tables, no shared status vocabulary, no cross-reference found anywhere.
- **Cooperative Offers are not Marketplace Orders.** Separate table, separate RPCs, writes to `member_sales_transactions` instead of `orders` — impossible to confuse at the database level.
- **Market Linking is independent of listings entirely.** Never touches `marketplace_listings`; its only shared surface with Marketplace is `inventory_batches`, and even that link is optional by design.
- **Inventory is never deducted twice.** A batch is touched exactly twice across its full journey — once at commitment, once at final settlement — confirmed never both in the same call, never redundantly.
- **Manual correction cannot violate committed stock — true today, not true in an earlier version of the fix**, disclosed above rather than glossed over.

---

# 5. Marketplace Orders

**Buyer places** (`place_order`) → `pending`. Row-locks the listing (`FOR UPDATE`), verifies `remaining_kg >= quantity`, decrements `remaining_kg`. Also checks the caller's own `user_roles.status = 'active'` at the RPC layer — a suspended account cannot order even if nothing in RLS alone stops the attempt.

**Widened in a later engagement — Farmer-to-Farmer Marketplace:** `place_order` no longer requires the caller to hold a `buyer`-role `user_roles` row specifically; it accepts `role IN ('buyer', 'farmer')` (`supabase_schema_place_order_farmer_purchasing.sql`), letting a farmer buy another farmer's listing through the identical RPC and the identical Buyer-side screens (`isFarmerContext: true`). The same migration added a **self-purchase guard** — `IF v_farmer_id = v_buyer_id THEN RAISE EXCEPTION 'You cannot place an order on your own listing'` — enforced at the RPC layer, not just withheld in the UI.

**Admin approves** (`approveOrder()`) → `approved`. **Corrected in a later engagement — this was previously documented as "Not an RPC."** It is now `approve_order(p_order_id)`, a `SECURITY DEFINER` RPC matching every sibling order-transition RPC's pattern exactly: internal `admin_profiles` check, `FOR UPDATE` row lock on the order, and a silent no-op (`RETURN FALSE`, no exception) if the order has already moved on from `pending` — preserving the same "can't double-notify on a race" protection the old client-side `.eq('status','pending')` conditional update provided, now enforced server-side instead of relying on RLS alone. Notifications also moved server-side into the RPC, and now go to **both** the buyer and the farmer (previously only the buyer, assembled client-side after the raw update succeeded).

**Admin completes** (`complete_order`) → `completed`. The one and only point in the Order lifecycle where `sold_kg` moves.

**Admin cancels** (`cancel_order`) → `cancelled`. **Tightened in a later engagement:** valid only from `pending` — previously also valid from `approved`, but once an order is approved the cooperative has committed to fulfilling it, and Complete Order is the only forward action left (`supabase_schema_cancel_order_pending_only_guard.sql`; the UI's Cancel button was already hidden once `approved`, this closes the same gap server-side). Restores the listing's `remaining_kg`; if the listing had flipped to `sold`, revives it to `approved`. The Cancel dialog now also requires a non-empty reason rather than treating it as optional.

**Buyer chooses fulfillment, added in a later engagement, not previously documented in this file:** once `approved`, the buyer (or farmer-as-buyer) selects Pickup or Delivery via `set_order_fulfillment(p_order_id, p_fulfillment_method, p_delivery_address, p_delivery_latitude, p_delivery_longitude, p_delivery_contact_number, p_delivery_notes)` — ownership-checked (`orders.buyer_id = auth.uid()`), no `admin_profiles` check at all (genuinely caller-agnostic between Buyer and Farmer-as-buyer), requires `status = 'approved'`, and requires a non-blank address + contact if `delivery` is chosen. Switching between the two is allowed at any point while still `approved`. This doesn't move `sold_kg`/`remaining_kg` — it's `orders`-table metadata only, which `AdminOrderDetailScreen` reads (including an embedded read-only map pin for a delivery address) so Admin knows how to arrange the sale. Admin never sets this — only the buyer does.

### Five distinct concepts, deliberately kept apart
Listing = the farmer's offer. Reservation = what that offer costs the batch. Order = one buyer's individual claim against the offer. Cooperative purchase = an entirely separate path where the cooperative is the buyer. Completed sale = the specific moment any of the three paths finally touches `sold_kg`.

No order state moves backward except `cancel_order`'s partial reversal — there is no "un-complete."

---

# 6. Cooperative Purchase Offers

**Why this workflow exists**, per `information.md` directly: for Palay and Peanut, the cooperative itself is the guaranteed buyer — a reliable market distinct from the open Marketplace, where a buyer might or might not appear.

**Widened in a later engagement, then given full financial parity in the Admin-Reports tab pass that followed.** Offer to Cooperative was originally hard-restricted to Palay/Peanut only, because `confirm_cooperative_offer` always settled into `member_sales_transactions`, whose `crop_type` was DB-constrained to those two crops. A prior engagement documented "Full Financial Parity" — widening that constraint so every crop settles the same way — as an explicitly deferred, future Reports-tab item, not yet implemented at that time. **That follow-through has since happened** (`supabase_schema_offer_to_cooperative_any_crop_transactions.sql`): the `crop_type` CHECK constraint was dropped entirely, and `confirm_cooperative_offer` was rewritten so there is now exactly **one** settlement path, not two:

**Farmer initiates** (`offer_batch_to_cooperative`, gated on `is_coop_eligible`) → reserves the offered quantity via the same `_apply_batch_reservation` primitive as Listings, but against a separate table row. `is_coop_eligible` is a `crop_master` GENERATED column, now derived from the crop's exclusive channel (`exclusive_channel IS NULL`) — **any crop except Ginger**.

**Admin confirms** (`confirm_cooperative_offer`) — every confirmed offer, for **any crop**, now writes a row into `member_sales_transactions` (`crop_type` stored as `lower(crop_name)`, no longer restricted to `'palay'`/`'peanut'`); `member_sales_transaction_id` is never left `NULL` for a real confirmation. There is no longer a per-crop branch: Palay, Peanut, and every other cooperative-eligible crop settle identically. This means **every** confirmed cooperative purchase now appears in the Sales Report, Analytics, and Balik-Tangkilik's math — not just Palay/Peanut. Palay and Peanut retain their own dedicated breakdown columns/UI in Sales Report and Member Patronage Report (for historical continuity — they were always the two dominant crops); every other crop is included in the same screens' totals under an "Other Crops" bucket rather than broken out by individual crop name.

Neither this nor any other path touches `inventory_batches.sold_kg` — see the correction in §4.

**Admin declines** → releases the reservation, no transaction record created, regardless of crop.

**Offer Details view — added in a later engagement.** Previously, a `confirmed`/`declined` offer card in `OfferToCooperativeScreen` was inert — `_OfferCard`'s `GestureDetector` only accepted taps `if (offer.isPending)`, so an already-decided offer showed its brief inline summary on the card itself (confirmed quantity + amount, or the decline reason) and nothing more; there was no way to open it for a fuller look. This is now closed, mirroring how Order Management opens `OrderDetailScreen` for a tapped order:
- **`pending` offers are unchanged** — tapping still opens `_ReviewOfferSheet`, the same confirm/decline form with the purchase-details fields, exactly as before.
- **`confirmed` (Approved) and `declined` (Rejected) offers now open a new, dedicated `OfferDetailScreen`** (`offer_detail_screen.dart`, routed at `AppRoutes.offerDetail`) instead of doing nothing. It is genuinely read-only — unlike `OrderDetailScreen`, which still exposes Approve/Cancel/Complete actions for a non-terminal order, an offer reaching either `confirmed` or `declined` is already terminal (see §5/§6's settlement discussion), so this screen has no bottom action bar at all, only information: a status card (badge + confirmed/declined subtitle + notes/reason), a farmer card (name, phone, avatar-or-initials — sourced from `user_information`, same join pattern `AdminOrderRepository.fetchOrderById()` already uses for a buyer), a batch/crop card (batch number, harvest freshness, category — sourced from `inventory_batches`/`harvest_records`/`crop_master`), and an offer-summary card (offered vs. confirmed quantity, amount paid, offered/confirmed dates).
- **New repository method:** `CooperativeOfferRepository.fetchOfferById(offerId)` — the same multi-step resolution pattern (base row → farmer info → batch/harvest/category info) `AdminOrderRepository.fetchOrderById()` already established, added because `fetchOffers()`'s list query deliberately doesn't resolve those extra fields for every row.
- **Model extended, not replaced:** `CooperativeOfferModel` gained optional, detail-screen-only fields (`farmerPhone`, `farmerPhotoUrl`, `batchNumber`, `harvestDate`, `category`, `confirmedAt`) — left `null` by `fetchOffers()`'s list query, populated only by `fetchOfferById()`, the same "detail-screen-only" convention `AdminOrderModel` already uses for its own equivalent fields.

### Relationship to Balik-Tangkilik

`member_sales_transactions.crop_type` is **no longer constrained** at the database level to `palay`/`peanut` — the CHECK constraint was dropped as part of the Full Financial Parity follow-through above. Every confirmed cooperative-purchase transaction, for any crop, counts toward Balik-Tangkilik's patronage-share math via the shared `fetchMemberSalesTotals()` aggregation (which buckets Palay/Peanut separately and everything else into `otherCropsQtyKg`/`otherCropsAmount`, all three summing into the one `totalAmount` Balik-Tangkilik actually distributes against). `contribution_id` on that table (nullable, FK to `member_contributions`) is **not currently populated by `confirm_cooperative_offer`**.

**This was investigated directly, not assumed to be a bug.** The actual Balik-Tangkilik computation (`refreshEstimates()`/`recordDistribution()`) aggregates `member_sales_transactions` by `farmer_id` + `sale_date` year — it never joins through `contribution_id`. The FK exists for potential future traceability, not because the current computation needs it. This also matches real-world timing: `member_contributions` rows are created once a year, in batch, around the Annual General Assembly — at the moment an individual offer is confirmed mid-year, the row it would link to usually doesn't exist yet.

**Immediate transaction logic** = the offer confirm/decline cycle itself, per-transaction. **Year-end cooperative accounting** = the separate Balik-Tangkilik aggregation pass, which reads the accumulated `member_sales_transactions` rows independently, on its own annual schedule.

---

# 7. Market Linking / DA-AMAD Pipeline

**What it represents:** the cooperative acting as a **broker, not a buyer** — connecting a farmer to an external buyer via DA-AMAD's Farmers and Fisherfolks Clustering Consolidation Program, with **no commission taken by the cooperative**, per `information.md` explicitly. **Firmed up in a later engagement:** this pipeline is no longer merely Ginger *by historical convention* — Ginger now carries `crop_master.exclusive_channel = 'da_amad_market_linking'`, an explicit reservation of the crop to one selling channel, enforced at three layers (farmer's Create Listing rejects it, Offer to Cooperative's `is_coop_eligible` excludes it, and Market Linking's own enrollment query resolves candidates through this classification — see below). Market Linking is Ginger's *only* disposal path.

**Why it's separate from Listings:** structurally never touches `marketplace_listings` at all — a completely independent table (`market_linking_programs`) with its own status vocabulary.

**Farmer enrollment — rebuilt in a later engagement, this section's original claim is no longer accurate (Confirmed by code + SQL, both Admin and Farmer screens read in full):** enrollment is now **farmer-initiated, admin-reviewed**, not admin-created. `enrollFarmer()` no longer exists anywhere in `market_linking_repository.dart` — it was removed along with the entire admin-direct enrollment flow (the "+" FAB and `_EnrollFarmerSheet` on `market_linking_screen.dart` are gone). A farmer with an approved Ginger crop in their Crop Roster submits an **Enrollment** request from `my_market_linking_screen.dart` (`submitEnrollment()` → RPC `submit_da_amad_enrollment()`), which inserts into a new table, `da_amad_enrollments` (`status`: `pending`/`approved`/`rejected`), guarded server-side against a farmer having more than one active (pending or approved) enrollment at a time and against enrolling without a Ginger crop. An admin reviews it from a **new dedicated screen**, `da_amad_enrollment_screen.dart` (routed as "Manage Enrollments," reachable via an icon button on the Market Linking screen's top bar), with Pending and Reviewed tabs; approving or rejecting calls `respond_to_da_amad_enrollment()`, which is one-time (a reviewed enrollment can't be re-reviewed from this screen) and sends the farmer a notification either way. The farmer's own `my_market_linking_screen.dart` view is **no longer purely read-only** — it has genuine farmer-initiated writes (submitting/resubmitting an enrollment) — but remains read-only about the specifics of any individual sale: buyer name/contact and the attached batch link are still deliberately never shown to the farmer on that screen, that part of the original claim still holds.

**Where the actual harvest submission now happens, added in this rebuild (Confirmed by code):** enrollment approval alone does not create a `market_linking_programs` row. Once approved, the farmer goes to **Manage Inventory** (a Harvest-tab screen) and submits one specific Ginger batch for sale via a "Submit to Sell" action — a single quantity field pre-filled with that batch's `available_kg`, capped at that value (not a picker across batches) — which calls `submitGingerForSale()` → RPC `submit_ginger_for_sale`. That RPC re-checks the caller has a currently-approved enrollment and that the batch belongs to them, then inserts the `market_linking_programs` row directly at `status='submitted'`, stamping an `enrollment_id` FK back to the approving enrollment row (`supabase_schema_market_linking_enrollment_link.sql`) — this is what used to be the admin-created "round." There is no per-harvest admin approval gate on this step at all; the batch's card in Manage Inventory shows "Enroll to Sell" until enrollment is approved, then "Submit to Sell," then "See Progress" once an active submission exists for that batch.

**Candidate resolution, corrected in a later engagement, and now largely superseded by the above:** `fetchEnrollmentCandidates()`/`fetchEligibleBatches()` previously identified Ginger growers via a fragile `ilike('crop_name', '%ginger%')` substring match on `crop_master`, later corrected to resolve through the crop's `exclusive_channel` instead. `fetchEnrollmentCandidates()` no longer exists at all (there is nothing left for an admin to "pick a candidate" from — enrollment is farmer-initiated). `fetchEligibleBatches()` remains, now used by Manage Inventory's own batch-eligibility check rather than by an admin candidate list.

**Status lifecycle — the old 'requested' gate retired, the rest unchanged:** `submitted` → `buyer_found` → `completed` or `cancelled`. Only `submitted`/`buyer_found`/`cancelled` are plain status flips with zero inventory effect. `completed` is the only state that can touch inventory, and only conditionally. The pre-Enrollment `'requested'` status (a per-harvest admin approve/decline gate) is fully retired as a reachable workflow — nothing creates it anymore, and no admin approve/decline UI for it exists; the enum value and its RLS policy remain in the database, unreferenced, per this project's convention of leaving retired DB objects in place. **Corrected in a later engagement: "Start New Round" no longer exists.** It was removed along with admin-direct enrollment — a "round" is now simply a farmer resubmitting a different (or the same, once free again) Ginger batch through Manage Inventory, not an admin action on a completed/cancelled card. A `cancelled` entry can still be permanently **deleted** — see §12's exception.

**Batch attachment — corrected again in this later engagement:** the batch is no longer resolved "automatically at the Buyer Found step." It is now attached **at submission**, by the farmer, since `submit_ginger_for_sale()` takes the specific `inventory_batch_id` being sold as a required parameter. It remains true that this is **not a dropdown/picker among several batches** — a farmer submits one specific batch's card directly, matching the one-farmer/one-harvest/one-buyer design. Admin's own "Enter Buyer Details"/"Complete Sale" sheet still auto-selects the batch (preferring the one already on the entry, else the farmer's most recent eligible Ginger batch) rather than offering a picker, and can re-attach a different batch via `attachBatch()` if needed before completion. When completed, `complete_market_linking` deducts `available_kg` and bumps `sold_kg` directly against that batch, in one atomic step (no intermediate "order" concept, matching the one-step nature of Cooperative Offer's settlement path). **Also hardened in a later engagement:** this RPC now includes an internal admin-authorization check and a batch-ownership check (the batch must belong to the farmer on the record being completed) that it previously lacked — the only two sibling finalization RPCs still missing that pattern before this fix (`supabase_schema_market_linking_complete_guard.sql`).

**Volume model — still three-tier, but the first tier's trigger point moved:** `volume_kg` (the farmer's committed volume — **now set at submission** via `submit_ginger_for_sale()`, not at enrollment; "enrollment" is now a separate program-membership gate that carries no volume of its own) → `requested_volume_kg` (the buyer's stated intent, set at the Buyer Found step — `supabase_schema_market_linking_requested_volume.sql`; shown to the farmer as "Buyer wants X kg", gated to `buyer_found`/`completed`) → `confirmed_volume_kg` (the final, actual settled volume, set at completion). These remain three genuinely distinct numbers at three distinct pipeline stages, not one field renamed.

**Buyers are never involved** — Market Linking has no concept of a Buyer-role user at all; the external buyer is an off-platform contact (`buyer_name`/`buyer_contact` free-text fields), not a SAGANA account.

**Market Linking = cooperative/DA-AMAD facilitation of an external, off-platform deal. Marketplace = an in-app transaction between a Farmer and a SAGANA Buyer account.** These are not variations of the same workflow; they represent two fundamentally different real-world relationships.

---

# 8. Admin Marketplace Dashboard

Every KPI traced to its exact source:

| Metric | Source | Calculation | Notes |
|---|---|---|---|
| Pending / Approved / Changes Required / Sold / Rejected listing counts | `AdminListingRepository.fetchSummaryStats()` | Server-side aggregate query, status column only | Matches `marketplace_listings` directly, no client-side filtering of a full fetch |
| Order counts (pending/approved/etc.) | `AdminOrderRepository.fetchSummaryStats()` | Same aggregate pattern | Matches `orders` directly |
| Market Linking KPI | `MarketLinkingRepository.fetchSummaryStats()` | Server-side aggregate | **This was corrected during this project's work** — originally a full-table fetch with a farmer-info join was pulled just to count two numbers client-side; replaced with a lightweight status-only aggregate, same output values. **Corrected again in a later engagement:** the KPI strip was showing raw row-count ("total rounds," including multiple rounds for the same farmer via the now-removed Start New Round) mislabeled as "Enrolled" — a real bug, caught via live testing. `MarketLinkingSummaryStats` now exposes a distinct `enrolledFarmers` (unique farmers, via a `Set`) alongside `totalRounds` (now removed from the visible KPI strip, see below), and a `cancelled` count. **A newer inconsistency, introduced by the Enrollment rebuild and not yet reconciled — flagging for awareness, not yet independently fixed:** the Marketplace Dashboard's own "Enrolled" tile still sources from `fetchSummaryStats().enrolledFarmers` (distinct farmers with a non-`'requested'` `market_linking_programs` row), but the Market Linking screen's own KPI strip now sources its "Enrolled" tile from a *different* number — `fetchReviewedEnrollments()`'s count of `approved` `da_amad_enrollments` rows. These are two different underlying facts ("has ever submitted a Ginger sale" vs. "has an admin-approved enrollment right now") that can diverge — e.g., an approved-but-not-yet-submitted farmer counts on the Market Linking screen's tile but not the Dashboard's, and a farmer whose enrollment was later rejected after a prior sale could count on the Dashboard's tile but not the screen's. Both figures are individually correct for what they measure; they are simply no longer the same measurement, unlike before this rebuild. The Market Linking screen's KPI strip also dropped its "Total Rounds" tile entirely, as a leftover from when Admin could directly create new rounds. |

**Removed in a later engagement:** the "Recent Listings" section (a horizontal list + "View All Listings" button) was removed from the Dashboard entirely, per request — the Quick Actions grid already has an "All Listings" tile, making the standalone section and button duplicative. The dashboard's KPI-tile-sourced consistency check below now covers Listings/Orders/Market Linking only, not a fourth "recent activity" source.

**Consistency check:** all summary-stat sources use the identical server-side-aggregate pattern (status column selected, tallied), so the dashboard's numbers are structurally guaranteed to match what the underlying list screens show for the same status filters — no separate, divergent counting logic exists anywhere in Marketplace.

---

# 9. Permissions & Authorization

### Admin
Full capability across every operation in every workflow: view, approve, reject, request changes, cancel, complete, delete (subject to the same status/ownership guards a farmer would also be subject to where relevant, e.g. `delete_listing`'s zero-orders requirement applies regardless of who's asking).

### Officer — resolved since the previous version of this document

This section previously documented a genuinely unresolved Staff authorization gap as the module's one open architectural question. **It is now closed — not by Marketplace itself, but as a direct, verified side effect of the separate Admin-Members module's Phase D-1/D-2 Officer rework.**

- **`staff_profiles.permissions` — including the `can_approve_listings` flag this section used to flag as unenforced — no longer exists.** It was dropped entirely, not fixed in place. Officer replaced Staff as a fixed role with no per-account permission configuration.
- **Every Officer now receives an `admin_profiles` row at account creation** (Create Officer Account, owned by the Admin-Members module). Every authorization check in this module (`approve_listing`, `reject_listing`, `approve_order`, `cancel_order`, `complete_order`, `confirm_cooperative_offer`, `decline_cooperative_offer`, `complete_market_linking`) still checks `admin_profiles` exclusively — re-confirmed directly against the live function bodies, unchanged from before — but that check is now genuinely true for an Officer session. (`request_listing_changes` was listed here in an earlier version of this document; it no longer exists — see §2–3's Changes Required removal note.)
- **No `is_authorized()` shared helper exists in this codebase**, and that observation still stands independent of the Officer fix: every function repeats its own inline `IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())` check.
- **Officer read access:** now identical to Admin across every Marketplace table — `marketplace_listings`, `orders`, `cooperative_purchase_offers`, `market_linking_programs` — since the same `admin_profiles` row that satisfies the RPC checks also satisfies every "admin manages all" RLS policy these tables carry. The earlier `marketplace_listings`-only Staff read gap no longer applies.
- **Route guards:** the `role == 'staff'` guards this section used to reference (`issueNewLoan` → `can_issue_loans`, `manageAdminAccounts` → `can_manage_accounts`) no longer exist. The only route-level Officer restriction left anywhere in the app is the Members-tab exclusion (Decision D19) — Marketplace has never had, and still doesn't need, any Officer-specific route guard.

**Net effect, stated plainly:** an Officer today can open the Marketplace tab, approve/reject listings, manage orders, and confirm/decline cooperative offers with exactly the same success as an Admin — the earlier contradiction between what the permission flag implied and what the backend actually allowed no longer exists, because the permission-flag model itself no longer exists.

**Re-confirmed in a later engagement:** every RPC touched by that engagement's work (`cancel_order`'s pending-only guard, `confirm_cooperative_offer`'s Scoped Fix rewrite, `create_listing_with_reservation`'s Ginger guard) still checks `admin_profiles` exclusively, the same inline pattern as before — Officer parity was not disturbed by any of this session's changes.

**Is the model consistent now?** Yes, for Officer specifically — database-enforced identically for Admin and Officer, with no UI/backend mismatch remaining. **Not yet independently re-verified with a fresh live Officer test in this module** — the RLS/RPC-body inspection above is direct and conclusive, but end-to-end Officer operational testing across the Admin system (Marketplace included) is intentionally deferred until the rest of the Admin system is complete, per the Admin-Members module's own documented testing plan — not because any code-level question remains open here.

---

# 10. RLS, RPCs, and Backend Security

| Operation | Repository method | RPC | Authorization | Tables affected |
|---|---|---|---|---|
| Create listing | `listing_repository.createListing()` | `create_listing_with_reservation` | Farmer's own auth session; **added in a later engagement:** rejects Ginger specifically (`supabase_schema_create_listing_ginger_guard.sql`) — Ginger can only be sold via Market Linking | `marketplace_listings`, `inventory_batches` |
| Approve listing | `admin_listing_repository.approveListing()` | `approve_listing` | `admin_profiles` + `pending_review`-only guard | `marketplace_listings` |
| Reject listing | `admin_listing_repository.rejectListing()` | `reject_listing` | `admin_profiles` + `pending_review`-only guard | `marketplace_listings`, `inventory_batches` |
| Withdraw listing | `listing_repository.withdrawListing()` | `withdraw_listing` | Farmer-own + status guard | `marketplace_listings`, `inventory_batches` |
| Delete listing | `listing_repository.deleteListing()` | `delete_listing` | Farmer-own + status + zero-orders guard | `marketplace_listings` |
| Place order | `buyer_marketplace_repository` | `place_order` | Buyer-or-farmer active-status check (widened in a later engagement) + self-purchase guard (added same engagement) | `orders`, `marketplace_listings` |
| Approve order | `admin_order_repository.approveOrder()` | `approve_order` *(added in a later engagement — was a raw `.update()`)* | `admin_profiles` + `pending`-only guard, `FOR UPDATE` | `orders` |
| Complete order | `admin_order_repository.completeOrder()` | `complete_order` | `admin_profiles` | `orders`, `marketplace_listings`, `inventory_batches` |
| Cancel order | `admin_order_repository.cancelOrder()` | `cancel_order` | `admin_profiles` + **`pending`-only guard, tightened in a later engagement** (was `pending` or `approved`) | `orders`, `marketplace_listings` |
| Set order fulfillment *(added in a later engagement)* | `buyer_order_repository.setFulfillment()` | `set_order_fulfillment` | Buyer/farmer-own (`orders.buyer_id = auth.uid()`) + `approved`-only guard | `orders` |

**"Request changes" and "Resubmit listing" rows, both listed in this table in an earlier version of this document, are removed** — `request_listing_changes` and `resubmit_listing_with_reservation` no longer exist (§2–3's Changes Required removal). Confirmed absent via a direct `pg_proc` query.
| Offer to cooperative | `cooperative_offer_repository` | `offer_batch_to_cooperative` | Farmer-own, `is_coop_eligible` check — **widened in a later engagement to any crop except Ginger** (was Palay/Peanut only) | `cooperative_purchase_offers`, `inventory_batches` |
| Confirm offer | `cooperative_offer_repository.confirmCooperativeOffer()` | `confirm_cooperative_offer` | `admin_profiles` + status guard | `cooperative_purchase_offers`; `member_sales_transactions` **only for Palay/Peanut** (rewritten in a later engagement — see §6); does **not** touch `inventory_batches` for any crop (see §4 correction) |
| Decline offer | `cooperative_offer_repository.declineCooperativeOffer()` | `decline_cooperative_offer` | `admin_profiles` + status guard | `cooperative_purchase_offers`, `inventory_batches` |
| Market Linking status change (non-completion) | `market_linking_repository.updateStatus()` | **None — raw `.update()`** | `market_linking_programs`' `Admin full access` RLS `FOR ALL` policy | `market_linking_programs` |
| Complete Market Linking | `market_linking_repository.updateStatus()` | `complete_market_linking` | `admin_profiles` + batch-ownership check | `market_linking_programs`, `inventory_batches` |
| Start New Round *(added in a later engagement)* | `market_linking_repository.startNewRound()` | **None — raw `.insert()`** | `market_linking_programs`' `Admin full access` RLS `FOR ALL` policy | `market_linking_programs` (new row, not a mutation of the terminal one) |
| Delete entry *(added in a later engagement)* | `market_linking_repository.deleteEntry()` | **None — raw `.delete()`** | Same RLS policy; UI restricts this action to `cancelled` entries only (no server-side status guard confirmed beyond RLS) | `market_linking_programs` — the one deliberate exception to this module's never-delete auditability floor, see §12 |
| Manual quantity correction | `inventory_repository.updateBatchQuantity()` | `update_batch_available_quantity` | Implicit via `SECURITY DEFINER`; bounded by current `available_kg`, never above it | `inventory_batches` |

**Where a raw `.update()` is still used instead of an RPC** (most Market Linking status transitions — **order approval no longer belongs in this category, see `approve_order` above**), it is safe specifically because the underlying RLS policy is `FOR ALL` and admin-gated — confirmed, not assumed, by reading the policy text directly rather than trusting the app's own restraint.

**UI-vs-backend consistency check, stated directly:** no situation was found where the UI permits an action the backend silently allows without an equivalent check — every write path traced has a real, independent backend guard. The Staff-era inconsistency this section used to note here (backend correctly blocking Staff while the UI implied capability that didn't exist) no longer applies — Officer's UI and backend now agree, both granting full capability.

---

# 11. Notifications

| Event | Recipient | Mechanism |
|---|---|---|
| Listing approved | Farmer | Insert inside `approve_listing`, `SECURITY DEFINER`. **This row previously read "not directly confirmed either way" — resolved during a later engagement's own work inside this function: confirmed present.** |
| Listing rejected | Farmer | Insert inside `reject_listing`, `SECURITY DEFINER` (bypasses the notifications table's own admin-gated INSERT policy, as intended) |
| Order placed | Admin | `place_order_admin_notify.sql` layer on `place_order` |
| Order approved *(added in a later engagement, moved server-side)* | Buyer **and** farmer *(previously buyer-only, assembled client-side after a raw update)* | Insert inside `approve_order`, `SECURITY DEFINER` |
| Order completed / cancelled | Farmer and/or Buyer | `order_notifications.sql` layer on `complete_order`/`cancel_order` |
| Cooperative offer confirmed / declined | Farmer | Insert inside the respective RPC, `SECURITY DEFINER` |
| Market Linking events | — | **Confirmed absent**, as of a later engagement's full read of `market_linking_repository.dart` and `my_market_linking_screen.dart` (previously stated as merely "not confirmed present"). No notification insert exists anywhere in `complete_market_linking`, the plain status-update path, `startNewRound()`, or `deleteEntry()`. The farmer's own Market Linking screen has no in-app awareness of a status change beyond opening the screen and pulling to refresh. |
| Order fulfillment chosen *(added in a later engagement)* | — | **Confirmed absent** — `set_order_fulfillment` has no notification insert. Admin sees the buyer's choice when they next open the order; not treated as needing a push notification since it isn't a state-machine transition. |

---

# 12. Marketplace History & Auditability

- **Permanent records:** `orders` and `member_sales_transactions` rows are never deleted by any Marketplace operation — cancellation and rejection change status, they don't remove the row.
- **One deliberate exception, added in a later engagement:** a `cancelled` Market Linking entry can now be permanently deleted (`market_linking_repository.deleteEntry()`). This is a genuine, intentional carve-out from the never-delete floor described below — justified because a cancelled enrollment carries no financial settlement and no buyer transaction record (Market Linking never creates one at all, per §7/§11), unlike a cancelled *order*, which still leaves its row behind. Restricted to `cancelled` entries in the UI; not confirmed to have an equivalent server-side status guard beyond RLS (see §10).
- **`delete_listing` is deliberately narrow:** only reachable from `withdrawn`/`rejected`, and only if the listing has **zero associated orders**, confirmed via the `delete_listing_order_guard`/`rejected_listing_terminal` guard chain. A listing that ever had any buyer interaction — even a cancelled one — cannot be deleted. This is the actual auditability floor: Admin can always reconstruct what happened to any listing that ever touched a real buyer.
- **Inventory reconciliation:** since every reservation/release/sale event is a deterministic function of the same four columns, and every state-changing RPC row-locks (`FOR UPDATE`) before mutating, a batch's current numbers are always explicable by tracing which of the known RPCs touched it — there's no untracked mutation path once M-8's RLS gap and M-9's manual-correction gap were both closed (see §17).
- **Verdict on sufficiency:** adequate for a cooperative of this scale and the workflows actually in use — the terminal-state deletion guard is the load-bearing protection, and it holds.

---

# 13. Marketplace → Reports

**Superseded by a full Sales Report redesign in the Admin-Reports tab pass — this section previously described an older architecture and has been corrected.** Sales Report is no longer a single-table view with a bolted-on Marketplace Revenue tile; it now unifies all four real Selling Types the organization actually recognizes — **Offer to Cooperative** (`member_sales_transactions`, any crop, per §6's full-parity fix), **Marketplace** (`orders` where `status = 'completed'`), **Informal Sale** (`informal_sales`), and **DA-AMAD Market Linking** (`market_linking_programs`) — as four tappable channel cards, each independently filterable, feeding one shared Transaction Details table and one combined Total Revenue figure (`fetchSalesReportForRange()` in `admin_reports_repository.dart`).

**Why this redesign happened:** before it, Informal Sale and DA-AMAD Market Linking were completely invisible to any report, and Marketplace Revenue existed only as a separate, redundant KPI tile alongside a Palay/Peanut-only itemized table — meaning three of the cooperative's four real sales channels either weren't shown together or weren't shown at all. The organization's own clarification (a crop's **Market Type** — Cooperative/Public/DA-AMAD — is a separate concept from its **Selling Type**, the actual channel a sale goes through) is what this redesign implements directly: Sales Report shows all four Selling Types, each tagged with Market Type where one meaningfully applies, but only **Offer to Cooperative** feeds Balik-Tangkilik's patronage math — the cooperative is the buyer in that channel alone.

**Why Balik-Tangkilik still only counts Offer to Cooperative:** Marketplace, Informal Sale, and DA-AMAD Market Linking are all channels where the cooperative is not the buyer (an outside buyer, an informal peer-to-peer sale, or a brokered external buyer, respectively) — full financial visibility for the BOD's own reporting is the reason all four now appear in Sales Report, but only a sale *to the cooperative itself* generates the cooperative profit Balik-Tangkilik actually redistributes.

**Date filtering:** all four channel queries filter on their own respective date columns (`sale_date`, `created_at`, etc.) using the same start/end range parameter passed into `fetchSalesReportForRange()` — confirmed consistent across all four, not independently drifting.

**"Full Financial Parity" — previously a documented, deliberately-deferred gap, now resolved.** This section previously stated that a confirmed cooperative sale of any crop other than Palay/Peanut was invisible to Sales Report, Analytics, and farmer earnings, because `member_sales_transactions.crop_type` was DB-constrained to those two values. **That gap has since been closed** (see §6): the CHECK constraint was dropped, `confirm_cooperative_offer` now settles every crop identically, and Sales Report/Member Patronage Report both roll any non-Palay/Peanut crop into an "Other Crops" bucket rather than excluding it. Every confirmed cooperative purchase, for any crop, is now visible end-to-end.

---

# 14. Marketplace → Analytics

`analytics_repository.dart` computes a `marketplaceRevenue` figure identically to the Reports version (`orders` filtered to `status = 'completed'`, summed) — same source, same filter, confirmed no divergence. Analytics combines this with cooperative sales and other operational KPIs into broader trend/forecast views, whereas **Reports presents operational summaries for a specific period** and **Analytics performs deeper aggregation/trend analysis across periods** — the distinction is genuinely about depth and time horizon, not about using different underlying data.

---

# 15. Cross-Module Integration

| Module | Relationship |
|---|---|
| **Admin Dashboard** | Reads `marketplace_listings`/`orders` counts for its own top-level KPIs; owns no Marketplace logic itself |
| **Admin Members** | No direct dependency found |
| **Admin Loans** | No direct dependency found |
| **Admin Inventory** | Marketplace reads/reserves against `inventory_batches`; does not own its lifecycle |
| **Admin Reports** | Sales Report unifies `orders`, `member_sales_transactions`, `informal_sales`, and `market_linking_programs` as four Selling Type channels — see §13 |
| **Admin Analytics** | Consumes `orders` identically to Reports — see §14 |
| **Farmer Harvest** | Creates `inventory_batches` rows Marketplace later reserves against — upstream of everything in this document |
| **Farmer Inventory** | Farmer's manual correction screen writes to `inventory_batches` via the same RPC Marketplace's reservation model depends on staying accurate |
| **Farmer Listings** | The farmer-facing half of the Listing lifecycle documented in §2–3 |
| **Farmer Market Linking** | Enrollment is admin-only; **the farmer's own visibility screen (`my_market_linking_screen.dart`) was read in full during a later engagement and confirmed genuinely read-only** — no action of any kind, buyer name/contact and any batch link deliberately never shown, only the farmer's own committed/requested/confirmed volume and status timeline |
| **Buyer Marketplace / Buyer Orders** | The buyer-facing half of §5, confirmed clean — read-only listing access plus `place_order`, no raw mutations found |
| **Notifications** | One-directional consumer of Marketplace events, via `SECURITY DEFINER` inserts that bypass the notifications table's own RLS — see §11 |
| **Balik-Tangkilik** | Consumes `member_sales_transactions` (populated by Cooperative Offer confirmation) for its annual aggregate computation — see §6 |
| **Database/Auth** | Every Marketplace authorization check ultimately depends on `admin_profiles`/`auth.uid()` — the Officer-authorization resolution in §9 is a direct consequence of this shared foundation, not something Marketplace introduced or resolved independently |
| **Officer Management** | Create Officer Account (owned by the Admin-Members module) is what grants the `admin_profiles` row Marketplace's own authorization checks rely on for Officer — see §9 |

---

# 16. Business Rules — Verified, Not Assumed

| Rule | Verified? | Evidence |
|---|---|---|
| A listing must be approved before buyers can see it | ✅ | `status = 'approved'` is the RLS-enforced buyer-read condition |
| Only Admin/Officer can approve/reject listings | ✅ (both hold `admin_profiles`; Farmer/Buyer excluded, see §9) | `admin_profiles` guard in `approve_listing`/`reject_listing` |
| Listings cannot exceed available inventory | ✅ | `create_listing_with_reservation` checks `available_kg >= requested` before reserving |
| Inventory cannot be double-reserved | ✅ | Confirmed no code path allows two simultaneous reservations to both succeed against insufficient stock — `FOR UPDATE` locking throughout |
| Orders cannot bypass the correct lifecycle | ✅ | Every transition RPC checks the required prior status explicitly |
| Cooperative Offers cannot be treated as Marketplace Orders | ✅ | Structurally separate tables, confirmed no cross-reference |
| Market Linking does not require a Marketplace listing | ✅ | Confirmed — never touches `marketplace_listings` |
| Completed transactions remain auditable | ✅ | Deletion guard in §12 |
| Inventory corrections cannot violate committed stock | ✅ **as of the corrected fix** — was **not** true in the first version, disclosed in §4 and §17 |
| Reports distinguish transaction types | ✅ | Four tappable Selling Type channel cards over four separate source tables, unified into one Sales Report, see §13 |
| Officer permissions are enforced consistently | ✅ **Now true** | See §9 — the earlier Staff-era inconsistency this row flagged has been resolved |
| Ginger cannot be listed on the Marketplace, offered to the cooperative, or informally sold — Market Linking is its only disposal path | ✅ *(added in a later engagement)* | Enforced at three independent layers: `create_listing_with_reservation`'s guard, `is_coop_eligible`'s generated-column exclusion, and the farmer disposal sheet hiding all three non-Market-Linking options for a Ginger batch |
| Offer to Cooperative accepts any crop except Ginger; every confirmation, any crop, is Balik-Tangkilik-eligible | ✅ *(widened, then given full financial parity in the Admin-Reports tab pass)* | `is_coop_eligible` GENERATED column + `confirm_cooperative_offer`'s single, crop-agnostic settlement path, see §6 |
| An order can only be cancelled while `pending`, never once `approved` | ✅ *(added in a later engagement)* | `cancel_order`'s tightened status guard, see §5, §10 |
| A farmer can browse and buy another farmer's listing, but never their own | ✅ *(added in a later engagement)* | `place_order`'s widened role check (`buyer` or `farmer`) plus its self-purchase guard, see §5 |
| Order approval, like every other order-status transition, is enforced by a guarded RPC, not a raw client update alone | ✅ *(closed in a later engagement)* | `approve_order`, see §5, §10 |
| A listing's review decision is binary — Approve or Reject — with no "needs changes" intermediate state | ✅ *(simplified in a later engagement)* | `changes_required` removed from the status CHECK constraint; `request_listing_changes`/`resubmit_listing_with_reservation` both dropped, see §2–3 |

---

# 17. Inconsistencies & Findings — Full, Honest Accounting

### Confirmed correct behavior
The entire Listing and Order state machines; Cooperative Offer/Marketplace Order separation; Market Linking's independence; the current (corrected) manual-quantity-correction ceiling; the Reports/Analytics Marketplace-revenue consistency; the deletion-based auditability floor.

### Confirmed bugs (all now resolved, disclosed with full history rather than presented as if they never happened)
- **Manual inventory correction, v1:** first fix bounded increases by `quantity_kg − sold_kg`, which ignored active reservations entirely and still permitted the exact overselling scenario it was meant to prevent. Caught during a subsequent fresh-verification pass, corrected to the current, mathematically sound rule (§4).
- **`inventory_batches` RLS over-tightening:** a fix meant to close raw `UPDATE`/`DELETE` around the reservation RPCs also removed `INSERT`, which broke live harvest-entry creation for every farmer (`403 Forbidden`). Caught in production, corrected within the same day by restoring `INSERT` alone while keeping `UPDATE`/`DELETE` closed.
- **`complete_market_linking` missing authorization + ownership checks:** unlike every sibling `SECURITY DEFINER` RPC in this module, it originally had no internal admin check and no verification that the attached batch belonged to the correct farmer. Corrected.
- **A stray UI-pattern deviation:** one screen used a raw bottom-sheet dialog instead of this project's established modal shell component. Corrected.

### Confirmed bugs — a later engagement's own findings (resolved, disclosed with the same full history)
- **Buyer Details' "Order History" was the live, actionable Order Management screen** — an admin could approve/cancel/complete a buyer's order from *inside their profile*, a path never meant to allow actions at all. Closed by a dedicated, genuinely read-only `buyer_order_history_screen.dart` that opens `OrderDetailScreen` in a `readOnly` mode; the same `readOnly` pattern was also applied to Listing Review so All Listings can no longer act on a listing it merely displays.
- **Rejected listings rendered with a green status badge** — the badge used a crude `isPending ? amber : green` binary instead of the correct, already-existing `ListingStatusDisplay.color` mapping. Corrected to use that mapping directly.
- **Market Linking's "Enrolled" KPI was actually a row count** — conflating a farmer with multiple rounds (via Start New Round) with multiple *farmers*. Corrected with a distinct `enrolledFarmers` (unique-farmer `Set`) versus `totalRounds`, at both the Market Linking screen and the Dashboard tile.
- **Market Linking's harvest-batch field was designed and first built as a dropdown/picker** — matching this document's own earlier §7 claim that attachment was "genuinely optional." Corrected per explicit design feedback: the workflow is one-farmer/one-harvest/one-buyer, so the field is now an automatic, locked link to the farmer's own batch, never a picker. This document's own earlier claim is what was wrong, not the code being newly broken — flagging that distinction plainly.
- **An All Listings card's image sat ~13px further right on pending cards than every other card** — traced to a left accent bar rendered only `if (listing.isPending)`, shifting all following content only for that one status. Fixed by always reserving the bar's space and toggling only its color.
- **A `RenderFlex overflowed` exception in Buyer Management's stats row** — pre-existing, surfaced only during live testing of an unrelated change. Fixed by wrapping the overflowing cluster in a `Flexible`.

### Architectural concerns
- **Resolved in a later engagement:** order approval was a raw client `.update()`, the one order-status transition in this whole module that hadn't gone through a guarded RPC (every sibling — `place_order`, `cancel_order`, `complete_order` — had one). Not a live exploit (the underlying RLS policy was correctly admin-gated), but a real inconsistency worth closing given this module's own stated architectural principle (§19: "the architecture intentionally prevents direct UI/database coupling"). `approve_order` now matches the pattern exactly, including the row lock the raw update never had.
- No shared `is_authorized()` helper exists — every RPC repeats its own inline admin check. Not a bug, but a maintenance-consistency risk: the pattern has to be remembered and reproduced correctly every time a new RPC is written, rather than centrally enforced.
- `reserved_kg` remaining as dead schema is technically harmless (nothing reads it) but is a latent source of confusion for anyone new to this codebase who reasonably assumes a column named `reserved_kg` is the authoritative reservation figure.
- **Newly identified in a later engagement, pre-existing rather than newly introduced:** a batch committed to a confirmed cooperative offer never has its `sold_kg` incremented (see §4's correction) — `available_kg` stays permanently decremented with no corresponding `sold_kg` credit, for any crop, including Palay/Peanut. This means inventory-level reporting that expects `sold_kg` to reflect all disposal paths would undercount cooperative-offer volume specifically. This was true of the canonical `confirm_cooperative_offer` before this engagement's Scoped Fix rewrite too — not something introduced by widening the crop scope. Documented here as a verified fact, not proposed as something to fix, per this document's documentation-only scope.

### Incomplete workflows
- Market Linking notification coverage is unconfirmed (§11) — genuinely unresolved, not investigated to a firm conclusion.
- `approve_listing`'s notification-to-farmer was not exhaustively confirmed either way.

### Permission gaps
- **None currently open.** The Staff/Marketplace gap this section previously documented in full — enforced correctly at the backend, contradicted by the permission model's own stated default, invisible to the user until they attempted the action — was resolved by the Admin-Members module's Officer rework (§9), not by a Marketplace-specific fix.

### Data-integrity risks
- None currently open. The two real ones found during this project's history (manual quantity correction, `inventory_batches` RLS) were both identified and closed, with the corrective process itself documented above rather than hidden.

### Documentation inconsistencies
- The project's own canonical-SQL reference notes were found to be stale in three places at one point (pointing to superseded files for `reject_listing`, `delete_listing`, `resubmit_listing_with_reservation`) — corrected during this project's work, with the correction itself documented in that file's own changelog-style addendum.

### Intentional design decisions (confirmed as such, not assumed)
- `contribution_id` left unpopulated by `confirm_cooperative_offer`.
- **Superseded by the Admin-Reports tab's Sales Report redesign:** the four Selling Types (Offer to Cooperative, Marketplace, Informal Sale, DA-AMAD Market Linking) are now unified into one Sales Report with one combined Total Revenue figure and four independently-filterable channel cards, rather than Marketplace revenue sitting as a separate KPI tile beside a Palay/Peanut-only itemized table — see §13.
- Raw `.update()` used instead of an RPC for order approval and most Market Linking transitions, relying on RLS as the actual enforcement layer.
- **Superseded, added in a later engagement:** Market Linking's batch attachment was previously an intentional *optional* field (row above no longer applies as of this document's §7 correction) — it is now an intentional *automatic and locked* field instead. Both were deliberate design choices at their respective times; the second supersedes the first, it isn't a bug fix reversing an accident.
- **Full Financial Parity — resolved, no longer deferred.** Offer to Cooperative confirmations, for any crop, now feed `member_sales_transactions`, Reports, and Analytics identically — see §6, §13. Farmer earnings (`DashboardRepository`'s "Total Earnings") was independently re-checked as part of this correction: it sums `member_sales_transactions.amount` with no `crop_type` filter at all, so it was already crop-agnostic before this fix and picks up non-Palay/Peanut cooperative sales automatically, with no code change of its own required.

---

# 18. UI/UX Evaluation (Observational Only)

- **Dashboard hierarchy:** logical — pending items and priority alerts surface above routine counts, matching what an admin would actually need to act on first.
- **Pending Approvals / All Listings:** clear, share a consistent filter pattern (now literally the same shared widget after this project's cleanup work).
- **Listing Review actions:** understandable; Approve now requires confirmation (added during this project's work, matching the friction level of comparable actions elsewhere in the module) — Reject/Request Changes require a written reason, which itself functions as an implicit confirmation step.
- **Order Management:** intuitive, consistent confirmation-dialog pattern across Approve/Complete/Cancel.
- **Cooperative Offers vs. Market Linking:** clearly separated as distinct screens with distinct terminology, matching their genuinely distinct backend workflows — no UI language was found conflating the two.
- **Status labels:** consistent with the underlying status enums, no cosmetic label found describing a state the backend doesn't actually have.
- **Empty states:** implemented consistently across the listing/order screens.
- **Superseded in a later engagement:** this section previously observed that Market Linking's batch attachment was optional but under-communicated in the UI. That premise no longer holds — batch attachment is now automatic and locked, not a field a user fills in or leaves empty at all, so there's nothing left to miscommunicate.
- **Filter consistency, resolved in a later engagement:** All Listings, Order Management, and Buyer Details' new Order History previously mixed a filter-icon-plus-modal pattern, a `TabBar`, and an ad-hoc chip style across different screens. All Marketplace list screens except All Listings (which keeps a filter icon by deliberate exception — its category filter has no natural chip-row equivalent) now share the same plain-pill `ListingStatusFilterChip` widget and the same fetch-once, client-side-filter switching behavior, so changing a filter no longer triggers a visible reload anywhere in this module.
- **All Listings image-alignment bug, resolved in a later engagement:** a left accent bar rendered only for pending cards shifted their image and text ~13px right relative to every other status — see §17.
- **Offer to Cooperative dead-end tap, resolved in a later engagement:** a `confirmed`/`declined` offer card was previously untappable — the only outcome information available was the brief inline summary already on the card itself, with no way to see the farmer's phone, the batch/harvest it came from, or the confirmed/declined date. It now opens a dedicated Offer Details screen, matching the drill-down affordance every other terminal-state Marketplace record already has (a completed/cancelled order, a completed/cancelled Market Linking entry) — see §6.

---

# 19. System Architecture

```
Flutter Screen (admin/*.dart)
      │  (zero raw Supabase calls confirmed anywhere in the 9 Marketplace screens)
      ▼
Repository (repositories/*.dart)
      │  (every mutation routes through either an RPC or a table whose RLS
      │   independently enforces the same authorization the RPC would have)
      ▼
Model (models/*.dart)
      │  (typed conversion, status enums, computed display fields)
      ▼
Supabase Client
      │
      ▼
SQL RPC (SECURITY DEFINER, internal admin/ownership/status checks)
      │              or
      ▼              raw query, gated by RLS policy directly
Postgres Database (marketplace_listings, orders, cooperative_purchase_offers,
                    market_linking_programs, inventory_batches, member_sales_transactions)
      │
      ▼
Other modules read the resulting state (Reports, Analytics, Balik-Tangkilik, Dashboard)
```

**Where the architecture intentionally prevents direct UI/database coupling:** every screen goes through a repository — confirmed, not assumed, by grepping for direct Supabase calls in all 9 Marketplace admin screens and finding none (`offer_detail_screen.dart` included — it goes through `CooperativeOfferRepository.fetchOfferById()`, no raw client call of its own). This means a screen can never accidentally skip a validation step the repository/RPC layer enforces, and it's also why the raw `.update()` calls (order approval, Market Linking status) are still safe — the *repository* is still the only caller, RLS is still the real gate, the app is just choosing not to wrap that particular call in an RPC because the RLS policy alone is already sufficient.

---

# 20. Required File Verification

Addressed at the top of this document.

---

# 21. Final Thesis-Defense Summary

### The three lifecycles, end to end

**Marketplace:** Farmer inventory (Harvest) → Listing created (with a required description, added in a later engagement), full quantity reserved immediately → Admin review — **simplified in a later engagement to a strictly binary decision, approve or reject; the "request changes" path was removed entirely** → if approved, publicly visible to Buyer **and, as of the same later engagement, to other Farmers acting as buyers** (Farmer-to-Farmer Marketplace, self-purchase guarded at the RPC layer) → an order is placed against the listing's own `remaining_kg` → Admin approves the order (`approve_order`, now a guarded RPC rather than a raw update, notifying both buyer and farmer) → the buyer chooses Pickup or Delivery (`set_order_fulfillment`, added in a later engagement) → Admin completes it, the one moment `sold_kg` finally moves → permanent `orders` record → feeds Reports' Marketplace Revenue tile and Analytics identically.

**Cooperative Purchase Offer:** Farmer offers an eligible batch — **any crop except Ginger**, widened from Palay/Peanut-only in a later engagement — → reservation applied → Admin confirms (every crop, any crop, writes `member_sales_transactions` identically, feeding the Sales Report's unified Selling Type breakdown and the annual Balik-Tangkilik aggregation — the earlier Palay/Peanut-only settlement split and its "Full Financial Parity" gap are both resolved, see §6) or declines (reservation released, any crop). Confirmation never touches `sold_kg` — see §4's correction. Either terminal outcome can now be reopened afterward, read-only, via the Offer Details screen — added in a later engagement, see §6.

**Market Linking:** Farmer enrolled by Admin → `submitted` → `buyer_found` (buyer's requested volume now captured, and the farmer's own Ginger batch auto-linked, not picked) → `completed` (`available_kg`/`sold_kg` move in one atomic step against that auto-linked batch) or `cancelled` (now deletable) → **Start New Round** creates a fresh entry rather than reopening the terminal one → no Buyer-role involvement, no Marketplace listing involvement, external buyer represented only as free text. Ginger is now this pipeline's exclusive crop by enforced classification, not mere convention.

### Fifteen questions, answered directly

1. **Primary responsibility:** to give farmers a moderated channel to sell inventory directly to buyers, while keeping that activity correctly separated from the cooperative's own direct-purchase and brokerage workflows.
2. **Data it owns:** `marketplace_listings`, `orders`, `cooperative_purchase_offers`, `market_linking_programs`.
3. **Data it merely consumes:** `inventory_batches` (owned by Harvest), `admin_profiles`/`officer_profiles` (owned by Auth/Members), `user_roles` (owned by Auth).
4. **Workflows it controls:** listing moderation, order lifecycle, cooperative offer confirmation, market-linking management.
5. **Workflows belonging elsewhere:** harvest logging and batch creation (Farmer Harvest), authorization architecture itself (system-wide, not Marketplace's to decide), Balik-Tangkilik's annual computation.
6. **Most important business rules:** full-quantity reservation at listing creation (not approval); the strict three-way separation of listing/inventory/order state; Cooperative Offers and Marketplace Orders can never be confused at the database level; deletion is permanently blocked once a listing has any order history; Ginger is excluded from every disposal path except Market Linking (added in a later engagement); Offer to Cooperative accepts any crop except Ginger, and every confirmation — any crop — is Balik-Tangkilik-eligible (full financial parity, Admin-Reports tab pass); an order can only be cancelled while `pending`; a listing's review decision is binary, Approve or Reject, with no intermediate "changes required" state (removed in a later engagement); a farmer can buy another farmer's listing but never their own (Farmer-to-Farmer Marketplace, self-purchase guarded).
7. **How inventory integrity is protected:** `FOR UPDATE` row-locking on every state-changing RPC, a single consistent reserve/release primitive shared across all three disposal paths, and — as of the corrected fix — a manual-correction ceiling that can no longer reopen active commitments.
8. **How permissions are enforced:** database-level, identically for Admin and Officer (RLS + per-RPC internal checks, both satisfied by the same `admin_profiles` row), with no shared central helper — each RPC repeats its own check.
9. **How transactions reach Reports:** `orders`, `member_sales_transactions`, `informal_sales`, and `market_linking_programs` all feed `fetchSalesReportForRange()` as four unified Selling Type channels on one Sales Report, sharing one Total Revenue figure and one Transaction Details table.
10. **How they reach Analytics:** the identical `orders`-completed-status aggregation as Reports for Marketplace Revenue specifically — confirmed same source, no divergence possible.
11. **Fully implemented workflows:** all four core lifecycles (Listings, Orders, Cooperative Offers, Market Linking) end to end.
12. **Incomplete workflows:** `approve_listing`'s farmer-notification remains unconfirmed either way — not investigated to a firm conclusion, the honest state is "unverified." Market Linking's notification coverage, by contrast, is **now confirmed absent** (a later engagement's full read of the repository and the farmer's own screen), not merely "unconfirmed present" as this document previously stated.
13. **Confirmed bugs:** the original four listed in §17, plus six more found and corrected during a later engagement (the Buyer-Details-Order-History mutation bug, the rejected-badge-green bug, the Market-Linking enrolled-vs-total-rounds KPI conflation, the batch-attachment dropdown-to-auto-link correction, the All-Listings image-misalignment bug, and a pre-existing Buyer Management overflow surfaced during live testing) — every one already found and corrected, with the corrective history itself part of the record rather than hidden.
14. **Intentional design decisions:** `contribution_id` left unpopulated, Market Linking's batch link now automatic/locked (superseding its earlier optional design). **No longer accurate for order approval, corrected in a later engagement:** raw `.update()` relying on RLS instead of a wrapping RPC — this was true of order approval when this document was first written; `approve_order` closed that specific gap (§5, §10), and the description now applies only to Market Linking's remaining raw-update transitions. **No longer a design decision, since implemented:** Full Financial Parity — Offer to Cooperative confirmations for any crop now feed Reports/Analytics identically, unified into Sales Report's four-channel design (§6, §13).
15. **Unresolved architectural decisions:** none remain for Marketplace specifically. The system-wide Staff authorization model this section previously flagged as open was resolved by the Admin-Members module's Officer rework (§9) — the only remaining item is a live, cross-module Officer operational/negative-path test, intentionally deferred until the rest of the Admin system is complete, not a design question.

---

*End of Final System Analysis & Documentation — Admin Marketplace Module.*

---

## Current state, 2026-10-24: 2 market types and 4 selling channels

This section replaces every earlier statement that treated DA-AMAD as a market type (`crop_type = 'da_amad_market'`). That value no longer exists anywhere in the database. SAGANA has exactly **two market types** and **four selling channels**, and they are different things.

**Market types decide who can see and buy a listing.** They are rows in the `market_types` table (name in English and Tagalog, `buyer_visible`, `manager_sets_price`, `sort_order`, `is_active`), not literals in code:

| Market type | Code | Who can see and buy |
|---|---|---|
| Public Market | `open_market` | Buyers and Farmer Members |
| Cooperative Market | `sp3_cooperative` | Farmer Members only (approved Farmers, Managers, Officers). Buyers can neither see nor purchase |

`crop_master.crop_type`, `crop_requests.crop_type`, `inventory_batches.crop_type`, `marketplace_listings.crop_type`, `cooperative_purchase_offers.crop_type`, `informal_sales.crop_type` and `price_records.price_type` are foreign keys to `market_types`, so a new market type is a new row, not a code change. A Farmer may buy another Farmer's listing, in either market, but never their own.

**Selling channels decide how a Farmer sells a harvested batch.** They are rows in `selling_channels`:

| Channel | Table(s) | Rule |
|---|---|---|
| Marketplace | `marketplace_listings` | A listing belongs to one market type; visibility follows it |
| Offer to Cooperative | `cooperative_purchase_offers` | Separate from Marketplace listings |
| Informal Sale | `informal_sales` | Records face-to-face or outside-system sales |
| DA-AMAD Market Linking | `da_amad_enrollments`, `market_linking_programs` | **Ginger only** (enrollment, harvest submission, the cooperative finds a buyer) |

**Ginger and DA-AMAD.** Ginger's `crop_master.crop_type` is `open_market` (Public Market). What makes it DA-AMAD-only is `crop_master.exclusive_channel = 'da_amad_market_linking'`: a crop reserved for exactly one selling channel. It can be set **only by a database administrator**: a trigger refuses it from the app (including a Manager), a unique index allows at most one crop per exclusive channel, and Crop Management shows it as read-only information. It is copied to `inventory_batches.exclusive_channel`, and `crop_master.is_cooperative_eligible` is now `exclusive_channel IS NULL`. Market Linking is deliberately **not** generalised to other crops.

**Backend enforcement (not only the screens):**
- Market visibility: `can_view_market_type()` (one rule); a restrictive read policy on `marketplace_listings` and on `price_records`; an order trigger (`trg_enforce_cooperative_market_order`) so a Buyer cannot order a Cooperative listing even by calling `place_order()` directly. A Buyer's own order history reads the listing details it needs through the `my_order_listings` view and `buyer_has_ordered_batch()`, so it never makes a farmer-only listing browsable.
- Channel rules: `enforce_selling_channel()` is attached to all four channel tables. A crop with an exclusive channel cannot use any other channel (this includes **Informal Sale**, which previously had no database guard), and DA-AMAD Market Linking refuses any crop that is not reserved for it. `create_listing_with_reservation`, `submit_ginger_for_sale`, `submit_da_amad_enrollment` and `approve_crop_request` now read these settings instead of the crop's name.
- A Manager changing a crop's market type updates its batches and its Pending/Live listings (`sync_market_type_from_crop_master`); Sold, Rejected and Withdrawn listings keep their original value.

**Manager Marketplace Management.** All Listings, Pending Approvals and Listing Review show a Public/Cooperative badge, and the first two have an "All markets / Public / Cooperative" filter (the chips come from `market_types`). Price Management builds one Reference Prices block and one Live Listings block **per market type** from the table; a listing's price can be corrected by the Manager only where `manager_sets_price` is true (today, the Cooperative Market). `admin_update_listing_price` checks the **listing's own** `crop_type`, not a lookup of the crop by name. Price notices (`notify_price_update`, new `p_price_type` argument) go to Farmers always and to Buyers only for a market they can see.

**Order wording.** The stored order statuses (`pending`, `rejected`) are unchanged. What people read is **Pending Order** (was "Pending Review") and **Disapproved** (was "Rejected"), on every Buyer, Farmer and Manager order screen, filter, detail and notification; the Manager's action reads "Disapprove Order". Database-written order notices are re-worded as they are stored (`trg_notifications_order_wording`), and existing ones were re-worded once. Listing statuses ("Pending Review", "Rejected" for a listing) are not orders and are unchanged.

**Scripts, in order:** `supabase_schema_market_types_channels.sql`, `supabase_schema_market_rules_by_data.sql`, `supabase_schema_order_wording_price_visibility.sql`. Tests: `supabase_schema_market_rules_test.sql` (database) and `test/market_visibility_rules_test.dart`, `test/inventory_source_and_order_wording_test.dart` (app).
