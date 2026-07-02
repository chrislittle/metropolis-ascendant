# Razing Lane — Build Spec (Issue #3)

**Goal:** make "destroy what you can't hold" a viable tool for a one-city (tall) player at higher difficulty,
**without** buffing a wide conquer-and-keep empire. Everything in this lane is tall-gated and is *penalty
relief* + *unlocking an existing reward*, never a new source of raw power.

## ✅ SHIPPED 2026-07-02 — final delivered design (read this first; the spec below is design history)

After in-game testing the original 7-item spec collapsed to **3 visible effects**, all burn-tolerant tall-gated
(`Settle $tallCap+1`), emitted once per FanOut Age in `MA_<sfx>_ATTACH_ALL`:

1. **Capture LUMP** — one-time **Gold (200/400/600) + Influence (50/100/150)** per city taken *by combat*.
   `EFFECT_CITY_GRANT_YIELD` on `COLLECTION_PLAYER_CITIES`, `permanent`, gated
   `REQUIREMENT_PLAYER_FIRST_TIME_SETTLEMENT_OCCUPATION` + `REQUIREMENT_CITY_TRANSFER_TYPE_MATCHES(BY_COMBAT)` +
   burn-tolerant tall. **Exact clone of Xerxes' `MOD_GOLD/CULTURE_ON_CAPTURE_SETTLEMENT`.** ScaleByGameAge extra=100.
   ✅ in-game confirmed (fires per capture, visible burst). Folds in the old Influence offset's job, VISIBLY.
2. **Pillage flat amp** — `EFFECT_ADD_PLAYER_UNITS_PILLAGE_BUILDING_PLUNDER` +10 Gold & +10 Science per building
   pillaged (on top of base 40+/building). ✅ in-game confirmed.
3. **Near-instant burn** — `EFFECT_CITY_ADJUST_RAZE_RATE` +999 on `COLLECTION_PLAYER_CITIES` (Fix A). ✅ confirmed
   (pop-8 city 7→3 turns; raze time is population-driven with steep diminishing returns, ~3 is the floor for a mid city).

**CUT after testing (all in §-history below):** Item 1 Influence offset (real but *invisible* — you can't see a
cancelled penalty, and the base capture dialog still hardcodes the "−N Influence" warning, so the UX contradicted it);
Item 4 tiny Sci/Cul floor (invisible); Item 7 ignore-capture-unrest (minor/invisible); Item 6 war-cap (never applied +
targeted over-cap unhappiness a tall player never reaches); Item 3b +%-plunder (never showed in the pillage preview);
Item 5 Suzerain (pre-existing, not part of this feature).

**The yield-crater during razing** (SOLO bonus gate off while the burning city is your transient 2nd settlement) is
**ACCEPTED** as a short ~3-turn dip, minimized by the maxed raze rate. **Zero-dip is PARKED** — feasible via an at-war
`OR`-gate but it's core-gate surgery (modifier requirement blocks are flat/no-nesting; the two Subject/Owner blocks AND
together and one holds the tech-node, so freeing a block for `(under-allowance OR at-war)` means relocating the node
gate mod-wide + a perpetual-war edge case). Not worth it to erase a 3-turn dip.

**Key design correction (Chris):** do NOT gate on founded-vs-conquered — the "count all settlements" model is correct
because taking a Distant Lands city *instead of* settling one is a legitimate metropolis and must keep its bonuses.

---

Status: **SHIPPED** (see above). Original spec below = design history.

---

## 1. Documented base-game razing model (web/data-verified 2026-07-02)

| Fact | Detail | Source |
|------|--------|--------|
| Razing duration | ~12 turns; destroys districts over turns (`CITY_RAZE_DISTRICTS_PER_TURN` = 2 EX / 3 MO) | Fandom Settlement / GameRant |
| Razing yields | **None** — the burning city produces nothing | GameRant |
| Reward path | **Pillaging** (separate unit action, before/independent of razing) — NOT the raze itself | Fandom Pillage |
| Pillage yields (per building) | Military/Science/Production → **40 Science/Age**; Culture/Happiness → **40 Culture/Age**; Food/Gold → **40/120/360 Gold** (by Age); Unique → 30–50 HP. Pillaged oldest-building-first, one per turn | Fandom Pillage |
| Settlement count during burn | A burning settlement **still counts as yours** → temporarily over settlement cap (over-cap unhappiness during the burn). NB the razed *Influence* penalty is NOT active yet during the burn — see next row | Fandom Settlement |
| Influence penalty | Ongoing Influence drain that **only starts AFTER the settlement is fully razed** ("after the entire settlement has been successfully razed"), runs **for the remainder of the current Age**, and **resets at Age transition**. Raw data: `EFFECT_PLAYER_ADJUST_YIELD_PER_RAZED_SETTLEMENT`, `YIELD_DIPLOMACY`, `-2` ScaleByGameAge → **−2/−4/−6** per razed settlement by Age (community reports ≈−8/turn; immaterial, see §5). **KEY:** because it begins post-burn, you are already back UNDER your settlement cap when it applies → the plain tall gate lines up, no buffer needed (see §4) | data + community |
| During-burn cost | While it burns you still own the conquered city, so the *conquered-ownership* penalty (`..._PER_CONQUERED_CITY`, −2/−4/−6) + over-cap unhappiness apply. We do NOT offset this (would buff conquer-and-keep); item 2 (faster burn) just shortens it | data |
| War Support penalty | **+1 permanent War Support against you per opponent** per razed settlement (no known softening effect) | GameRant |
| Diplomatic relationship hit | A one-time **Relationship** penalty with the affected leader (internal `GrievancesGiven=5000` on `CITY_RAZED`/`TOWN_RAZED` feeds it). **NOT a surfaced "Grievances" stat** — Grievances were a Civ VI mechanic; Civ VII runs on Relationships + Influence, so the player just sees the leader like them less. No known softening effect | data (`diplomacy-actions.xml`) |
| Razed-count requirement EXISTS | `REQUIREMENT_PLAYER_RAZED_X_CITIES` (Amount threshold; base uses `Amount=1` for a Wonder unlock). Increments on raze *completion*. Not needed for the offset gating, but **revives the deferred tiered-reward ideas** (first-raze-cheap, escalating curve, bigger payoff at raze ≥N) — see §6 | data (`unlocks.xml`) |

**Design takeaways:** (a) the reward already exists and is big and size-scaled — we don't invent one, we make
razing survivable so the tall player can sack-then-raze; (b) the real cost we can cleanly touch is the over-cap
window during the burn (the post-burn Influence drain we fully offset); (c) War Support and the Relationship hit
are out of reach and stay as the "razing is still a serious decision" texture.

---

## 2. Design principles

1. **Relief, not power.** We cancel the Influence drain and shorten the burn; we do not hand out free yields
   beyond a token floor. The headline "reward" is the base-game pillage the player earns by fighting.
2. **Tall-gated throughout.** A wide conquer-and-keep empire gets none of it. See §4 — the gate is the whole
   anti-abuse story.
3. **Mirror the base effect for the offset** so it self-matches the penalty magnitude and Age-scaling, and only
   ever nets to ~zero (never net-positive Influence from razing).
4. **Use only proven collections.** Faster-burn uses the exact collection the base game uses for that effect
   (`COLLECTION_UNIT_OCCUPIED_CITY`, Qajar Soltan), so no undocumented behavior is assumed.

---

## 3. Shippable items

### Item 1 — Influence-penalty offset (core)
- **Effect:** `EFFECT_PLAYER_ADJUST_YIELD_PER_RAZED_SETTLEMENT`, `COLLECTION_OWNER`.
- **Args:** `YieldType=YIELD_DIPLOMACY`, `Amount type="ScaleByGameAge" extra="100"` = **+2** → **+2/+4/+6** by Age.
- **What it does:** exact positive mirror of the base razed-Influence drain, netting the *ongoing* penalty to
  zero for a tall razer. Because it uses the same effect + ScaleByGameAge, it tracks the penalty in every Age
  and needs only to hold within an Age (penalty resets at transition).
- **Does NOT** touch the +War Support or the −100 diplo hit (no effect exists).

### Item 2 — Faster burn (shorten the over-cap/spike window)
- **Effect:** `EFFECT_CITY_ADJUST_RAZE_RATE`, `COLLECTION_UNIT_OCCUPIED_CITY` (proven: Qajar `SOLTAN_MOD_RAIZING`).
- **Args:** **`Amount=2`** (+2 districts destroyed/turn on top of base). Rate = districts destroyed per turn;
  turns-to-raze = districts ÷ rate. Base `CITY_RAZE_DISTRICTS_PER_TURN` = **2 EX / 3 MO** (no Antiquity override
  found — uses base default, confirm in tuning). So +2 → **EX 2→4 (2×, half the turns)**, **MO 3→5 (+67%)**.
  `OwnerRequirements` = `REQUIREMENT_UNIT_IS_STATIONED_ON_DISTRICT` + the burn-tolerant tall gate (§4).
- **What it does:** roughly halves the burn (in EX), the mitigation for the one real during-burn cost — the
  over-cap unhappiness while a burning city counts against your limit. Must be live *while* the city burns (you're
  over cap then), so it uses the burn-tolerant gate, NOT the strict SOLO gate (§4).

### Item 3 — Pillage amplifiers (optional; make the existing reward pop)
The base pillage yields (40+/building, Age-scaled) are already the size/district-scaled reward. These only
amplify, and are optional / conservative first numbers:
- **`EFFECT_ADD_PLAYER_UNITS_PILLAGE_BUILDING_PLUNDER`** (`COLLECTION_OWNER`, player-wide — proven Sayyida shape):
  flat **+Amount per building pillaged**, one modifier per `PlunderType`. First pass: **+10 `PLUNDER_GOLD`**,
  **+10 `PLUNDER_SCIENCE`** (tune).
- **`EFFECT_ADJUST_UNIT_PLUNDER_YIELDS`** (`COLLECTION_PLAYER_UNITS`): **+% to all plunder**. First pass:
  **+25** (Pirate Black Flag uses 50/100 — keep conservative).
- **(Lower confidence, optional) `EFFECT_PLAYER_ADJUST_UNIT_CAPTURE_ADDITIONAL_BOOTY`** (`COLLECTION_OWNER`,
  `Amount`): extra one-shot booty on capture — booty currency unconfirmed; hold unless a quick check shows it's Gold.

### Item 4 — Small flat per-razed floor (optional flavor)
- **Effect:** `EFFECT_PLAYER_ADJUST_YIELD_PER_RAZED_SETTLEMENT`, `COLLECTION_OWNER`, `YIELD_SCIENCE` **+1** and
  `YIELD_CULTURE` **+1**, ScaleByGameAge → +1/+2/+3 each per razed settlement.
- **What it does:** a token ongoing reward so razing an already-pillaged husk still gives *something*. Kept small
  precisely because pillaging (Item 3's base) is the real reward.

### Item 5 — Suzerain Influence (already shipped; framing only)
`M-SuzerainDiplo` (+2 Influence/suzerain) already exists and, once Item 1 stops razing from draining Influence,
is the standing income that funds a war. No new work.

### Item 6 — War-time settlement-cap relief (the over-cap offset) — CORE
Handles the one happiness cost that actually hits the metropolis: while a captured/burning city puts you over your
settlement cap, `EFFECT_CITY_ADJUST_YIELDS_PER_SETTLEMENT_OVER_CAP` docks **−5 Happiness per city**
(gated `REQUIREMENT_PLAYER_OVER_SETTLEMENT_CAP`).
- **Effect:** `EFFECT_PLAYER_ADJUST_SETTLEMENT_CAP`, `COLLECTION_OWNER`, **Amount +1**.
- **Gate:** `REQUIREMENT_PLAYER_HAS_X_WARS` (`Amount=1`) **+ tall (`$tallCap`)**.
- **What it does:** while you're at war your cap rises by 1, so the transient captured/burning settlement doesn't put
  you over cap → the −5 penalty never fires. At **peace the +1 drops off**, so you cannot keep a second city happily —
  tall enforcement is fully preserved, and a wide warmonger is excluded by the tall gate.
- **Why this gate:** a tall player only acquires transient settlements *during a war*, and "at war" is a clean,
  non-circular, continuously-evaluated signal — unlike `REQUIREMENT_PLAYER_OVER_SETTLEMENT_CAP` (circular for a cap
  grant) or `REQUIREMENT_PLAYER_RAZED_X_CITIES` (only counts *completed* razes). There is no clean player-level
  "currently razing" requirement, so war-context is the right proxy.
- **Note:** this does NOT change the settlement *count*, so the burn-tolerant gate (§4) is still needed for Items 2/3;
  it only removes the over-cap *unhappiness*. Ignore-unhappiness can't be used here (over-cap is a Happiness yield
  reduction, not a named `UnhappinessEffect` enum).

### Item 7 — Ignore capture unrest (optional)
- **Effect:** `EFFECT_ADJUST_CITY_IGNORE_UNHAPPINESS_EFFECT`, `COLLECTION_PLAYER_CITIES`, `UnhappinessEffect=CityTransferUnrest`
  (proven — base Militaristic attribute node `MOD_ATTRIBUTE_MILITARISTIC_05`).
- **What it does:** removes the `CityTransferUnrest` −15 Happiness / 10 turns capture penalty. Lower value for a razing
  player (the captured city is being destroyed anyway); include only if we want war happiness fully smooth. Tall-gated.

---

## 4. Gating to tall — the anti-abuse mechanism

Conquest/razing **temporarily inflates your settlement count** (occupied + burning cities count as yours). This
splits the lane into two gating groups depending on *when* each item needs to be active:

**Group A — items that matter POST-burn → plain SOLO gate (no buffer).**
- **Item 1 (Influence offset)** and **Item 4 (flat floor)**: the razed penalty (and the reward they pay) only
  exist *after* the settlement is fully razed (§1), by which point the burning city is gone and you're **back
  under your normal cap**. So the mod's standard SOLO gate — `REQUIREMENT_PLAYER_HAS_X_SETTLEMENTS` inverse at
  `$tallCap`, the exact gate every other player-wide bonus uses — already lines up. **No special handling.** (The
  per-razed effect also pays 0 if you haven't razed, so no razed-count requirement is needed either.)

**Group B — items that must run DURING the burn/war → burn-tolerant gate.**
- **Item 2 (faster burn)** runs while the city burns, when you're transiently over cap; **Item 3 (pillage amps)**
  run through a siege where capture timing may inflate the count. A strict SOLO gate would blink these off exactly
  when needed. Use `REQUIREMENT_PLAYER_HAS_X_SETTLEMENTS` (inverse, all settlements) at **`$tallCap + 1`**:
  - Antiquity: fewer than **3** total (founded 1 + one in-flight = 2 → passes).
  - Exploration / Modern: fewer than **4** total (1 Homeland + 1 Distant + one in-flight = 3 → passes).
  The **+1 buffer admits only the transient bulge of an active war**, not permanent holdings — a conquer-and-keep
  empire sits well past it and gets nothing. The buffer is the tuning dial (raise for simultaneous multi-city razes,
  lower toward strict SOLO if too permissive).

**Why NOT gate Group B on `REQUIREMENT_PLAYER_RAZED_X_CITIES` instead:** it only increments on raze *completion*, so
on your *first* raze the count is still 0 throughout that burn — faster-burn would never fire for the first city.
The burn-tolerant settlement threshold is the correct tool; the razed-count requirement is reserved for tiered
rewards (§6).

---

## 5. Per-Age summary (per razed settlement, tall razer)

| | Antiquity | Exploration | Modern |
|---|---|---|---|
| Base Influence drain | −2/turn | −4/turn | −6/turn |
| **After Item 1 offset** | **≈0** | **≈0** | **≈0** |
| Item 4 floor (optional) | +1 Sci, +1 Cul | +2 Sci, +2 Cul | +3 Sci, +3 Cul |
| Burn length (Item 2, +2) | shorter | 2→4 districts/turn (2×) | 3→5 districts/turn (+67%) |
| **Pillage reward (base, per building)** | 40 Sci **or** 40 Gold | 40 Sci **or** 120 Gold | 40 Sci **or** 360 Gold |
| Pillage amp (Item 3, optional) | +10 flat & +25% | +10 flat & +25% | +10 flat & +25% |
| War Support (+1/opponent) | unchanged | unchanged | unchanged |
| Relationship hit | unchanged | unchanged | unchanged |

**On the −8 vs −2/−4/−6:** immaterial. Item 1 mirrors the *effect*, so it cancels the drain whatever the true
displayed magnitude; if playtest shows residual drain, bump Item 1's base from +2 to +3.

---

## 6. Deliberately out of scope (documented as not-worth-it or unsupported)
- **Reward by target population (size)** — no effect reads a captured/razed settlement's population. Districts
  (via pillage) are the only size proxy, and they're already covered.
- **City-vs-town differentiated penalty/reward** — only reachable via the discrete `GOSSIP_CITY_RAZED01`
  narrative hook (own subsystem, shared cost with "Arcadia Awakens"); deferred.
- **Softening +War Support or the Relationship hit** — no effect exists; kept as "razing is still serious" texture.

**Back ON the table (via `REQUIREMENT_PLAYER_RAZED_X_CITIES`, Amount threshold — found 2026-07-02):**
- **Tiered / escalating rewards** — gate progressively larger rewards on razed ≥1 / ≥3 / etc., or a "first raze is
  cheap" band. Earlier marked unsupported (thought no razed-count requirement existed); it does. Candidate for a v2
  pass on this lane, not the first cut.
- Note it still can't gate the *during-burn* items (increments only on completion, §4).

---

## 7. Build / verify notes
- Lane is player-wide + one per-unit-collection item; emit once per FanOut Age like the Suzerain layer, add ids to
  each Age's `MA_<sfx>_ATTACH_ALL` wrapper (Item 2's `COLLECTION_UNIT_OCCUPIED_CITY` modifier attaches the same way).
- **No litmus playtest required for the mechanics** — docs answered the two open behaviors (settlement counts during
  burn = yes; raze itself yields nothing). The only in-game confirm left is *balance* (does the tolerant gate feel
  right, are the amp numbers hot) — a normal Deity tuning pass, not a feasibility test.
- One tiny optional check: whether `CAPTURE_ADDITIONAL_BOOTY` pays Gold (Item 3 last bullet) before including it.
- LOC: `LOC_MA_RAZE_*` tooltip strings; regen bonus-list / change-note / steam description as usual.
