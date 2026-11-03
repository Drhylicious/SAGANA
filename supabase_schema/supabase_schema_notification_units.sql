-- ============================================================
-- SAGANA — Notifications and messages name the batch's own unit (not "kg")
--
-- WHY
--   Offer to Cooperative, Market Linking (Ginger), the Marketplace listing notice and
--   the "not enough stock" order message all had the word "kg" written into their
--   text, even though the quantity can now be in any unit recorded on the harvest
--   (sack, piece ...). A farmer who offered 3 sacks was told "3 kg".
--
-- HOW (and why it is done this way)
--   This file does NOT paste a copy of each function. A copy could silently put an
--   older version over a newer one. Instead it reads each function's LIVE
--   definition from the database (pg_get_functiondef), replaces only the exact
--   pieces of message text listed below, and re-creates the function. A piece that
--   is not found is skipped and reported, so a function that was already changed
--   is left alone. Nothing but message text is touched. Safe to re-run: once
--   replaced, a piece is no longer found.
--
--   The unit comes from the same row the message is already about:
--     offers            v_offer.unit  (cooperative_purchase_offers.unit)
--     new offer         the batch's unit (inventory_batches.unit)
--     Market Linking    v_prog.unit   (market_linking_programs.unit)
--     new listing       the batch's unit
--     order too large   the listing's unit
--
-- Run AFTER supabase_schema_ginger_any_unit.sql (it adds market_linking_programs.unit).
-- Not applied automatically. The NOTICE lines show what was changed or skipped.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'market_linking_programs' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_ginger_any_unit.sql first (market_linking_programs.unit is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'cooperative_purchase_offers' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'cooperative_purchase_offers.unit is missing. Run supabase_schema_harvest_batch_number_and_units.sql first.';
  END IF;
END;
$$;

CREATE TEMP TABLE _unit_patch (fn TEXT, needs TEXT, frag TEXT, repl TEXT) ON COMMIT DROP;

-- ─── Offer to Cooperative: the offer row carries the unit ─────────────────
INSERT INTO _unit_patch (fn, needs, frag, repl)
SELECT f.fn, 'v_offer', p.frag, p.repl
FROM (VALUES ('counter_cooperative_offer'), ('accept_cooperative_offer'), ('decline_cooperative_offer'),
             ('cancel_cooperative_offer'), ('deliver_cooperative_offer'), ('confirm_cooperative_offer_receipt'))
     AS f(fn)
CROSS JOIN (VALUES
  ($f$' kg '$f$,               $f$' ' || COALESCE(v_offer.unit, 'kg') || ' '$f$),
  ($f$'/kg (total '$f$,        $f$'/' || COALESCE(v_offer.unit, 'kg') || ' (total '$f$),
  ($f$'/kg for '$f$,           $f$'/' || COALESCE(v_offer.unit, 'kg') || ' for '$f$),
  ($f$'/kg for your '$f$,      $f$'/' || COALESCE(v_offer.unit, 'kg') || ' for your '$f$),
  ($f$The kg were returned to your inventory.$f$, $f$The quantity was returned to your inventory.$f$)
) AS p(frag, repl);

-- ─── A new offer: no offer row yet, so the batch's unit ───────────────────
INSERT INTO _unit_patch (fn, needs, frag, repl) VALUES
  ('offer_batch_to_cooperative', 'v_batch',
   $f$' kg ' || v_batch.crop_name$f$,
   $f$' ' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ' ' || v_batch.crop_name$f$),
  ('offer_batch_to_cooperative', 'v_batch',
   $f$'/kg and needs a response.'$f$,
   $f$'/' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ' and needs a response.'$f$);

-- ─── Ginger / DA-AMAD Market Linking ──────────────────────────────────────
INSERT INTO _unit_patch (fn, needs, frag, repl)
SELECT f.fn, 'v_prog', p.frag, p.repl
FROM (VALUES ('record_market_linking_sale'), ('close_market_linking_request'),
             ('request_market_linking_cancellation'), ('respond_to_market_linking_cancellation'))
     AS f(fn)
CROSS JOIN (VALUES
  ($f$' kg of '$f$,                          $f$' ' || COALESCE(v_prog.unit, 'kg') || ' of '$f$),
  ($f$' kg is back in your stock.'$f$,       $f$' ' || COALESCE(v_prog.unit, 'kg') || ' is back in your stock.'$f$),
  ($f$' per kg (total '$f$,                  $f$' per ' || COALESCE(v_prog.unit, 'kg') || ' (total '$f$),
  ($f$' kg is still in your request.'$f$,    $f$' ' || COALESCE(v_prog.unit, 'kg') || ' is still in your request.'$f$),
  ($f$' kg unsold). Reason: '$f$,            $f$' ' || COALESCE(v_prog.unit, 'kg') || ' unsold). Reason: '$f$),
  ($f$' kg already sold stays recorded.'$f$, $f$' ' || COALESCE(v_prog.unit, 'kg') || ' already sold stays recorded.'$f$)
) AS p(frag, repl);

-- ─── Marketplace: the staff notice for a new listing, and the order message ─
INSERT INTO _unit_patch (fn, needs, frag, repl) VALUES
  ('create_listing_with_reservation', 'p_batch_id',
   $f$'kg) was submitted for review.'$f$,
   $f$' ' || COALESCE((SELECT unit FROM public.inventory_batches WHERE id = p_batch_id), 'kg') || ') was submitted for review.'$f$),
  ('place_order', 'p_listing_id',
   $f$Only % kg remaining.', v_remaining;$f$,
   $f$Only % % remaining.', v_remaining, COALESCE((SELECT l2.unit FROM public.marketplace_listings l2 WHERE l2.id = p_listing_id), 'kg');$f$);

-- ─── Apply ────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r      RECORD;
  v_def  TEXT;
  v_new  TEXT;
  q      RECORD;
  v_hits INT;
  v_done INT := 0;
  v_skipped INT := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname, p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    WHERE p.proname IN (SELECT DISTINCT fn FROM _unit_patch)
    ORDER BY p.proname
  LOOP
    v_def  := pg_get_functiondef(r.oid);
    v_new  := v_def;
    v_hits := 0;
    FOR q IN SELECT * FROM _unit_patch WHERE fn = r.proname LOOP
      IF position(q.needs IN v_new) > 0 AND position(q.frag IN v_new) > 0 THEN
        v_new  := replace(v_new, q.frag, q.repl);
        v_hits := v_hits + 1;
      END IF;
    END LOOP;

    IF v_new <> v_def THEN
      BEGIN
        EXECUTE v_new;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Could not re-create % after changing its message text: %', r.sig, SQLERRM;
      END;
      v_done := v_done + 1;
      RAISE NOTICE 'CHANGED  % (% message piece(s))', r.sig, v_hits;
    ELSE
      v_skipped := v_skipped + 1;
      RAISE NOTICE 'unchanged % (nothing to replace: already unit-aware, or text differs)', r.sig;
    END IF;
  END LOOP;

  RAISE NOTICE 'Done: % function(s) changed, % unchanged.', v_done, v_skipped;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY CHECK (read-only) ───────────────────────────────────────
-- Functions whose message text still says "kg" next to a number. Expect none of the
-- functions named above; anything else listed is outside this file's scope:
--   SELECT p.oid::regprocedure AS function
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
--   WHERE pg_get_functiondef(p.oid) ~ $q$' kg |/kg |kg\) was|per kg \(total|Only % kg$q$
--   ORDER BY 1;
