# Planned Feature — "Tall Resource Reach" (the Surveyor)

Status: **PLANNED / RESEARCHED — build when credits reset (target Fri 2026-07-03).**
Owner: Chris. All mechanics below were CONFIRMED in-game or against installed base-game data
during the 2026-06-30 research session — not guessed. Read this whole doc before building.

---

## 1. One-line summary

A tall metropolis periodically receives a **dedicated "Surveyor" unit** (granted at population
**milestones**) that can walk out and **claim a resource tile up to 5 hexes from a settlement**,
pulling it (and its strategic/bonus/empire yields) into your borders — amplified by a Metropolis
Ascendant **per-resource** bonus. Tall-gated. Data-only, no scripting.

## 2. Why THIS form (the research journey — don't re-litigate these)

The original goal was "work tiles out to ring 5 like the Civ6 neighborhood-tall mod." We proved,
in order:

1. **`city.Growth.claimPlot({x,y})` DOES break the 3-hex cap** (FireTuner, live): claimed dist-4
   tiles, and the engine *worked* them + paid yields. So the "3-hex limit" is a **natural-EXPANSION
   cap, not a working cap** — own a tile by any means and the engine works it… **IF it has yield**.
2. **But claimPlot is unshippable.** It only mutates in the gameplay V8 isolate, which Civ7 does
   **not** expose to mods (`<ScenarioScripts>` never executed in a normal game; community-confirmed:
   "gameplay scripts don't seem to be possible"). UI-isolate `claimPlot` is a no-op. There is **no
   custom UI→gameplay RPC**. So a script-driven claim cannot ship.
3. **Native claim paths checked:** city EXPAND = hard-capped at 3; diplomatic `LAND_CLAIM` operation
   = won't touch wilderness (needs a target player); **the Prospector's `UNITCOMMAND_CLAIM_RESOURCE`
   = WORKS.** Chris-confirmed from play + our Explorer test: it claims a **resource** tile **within 5
   hexes of a friendly settlement** and **brings it into your territory**. The resource rule is
   **native** (the command row is bare `Type`+`Kind`; no data requirement to remove) — so it's
   resource-tiles-only, not general tiles. Accept that.
4. **The empty bridge tiles can't be made productive.** In-game (WASET, Modern): a claimed flat
   desert tile is **unimproved and unworkable** — Chris could not assign a citizen to it (range-3 caps
   *working/improving*, not just claiming). A per-type yield modifier (`EFFECT_PLOT_ADJUST_YIELD`,
   `TEST_DESERT_YIELD`) **did land on the tile** (showed +5) but the city **never collects it** because
   it can't work the tile. And there is **no "yield per owned tile/terrain" effect** to bypass working.
   So empty outer tiles = territory only. Resource tiles self-improve (extraction outpost) → productive.
5. **Conclusion:** the shippable value is **resources**, and the engine is full of **per-resource**
   amplifiers → lean into resources, not empty tiles.

## 3. The design

- **Dedicated Surveyor unit** (Chris's call — NOT tagging all base Migrants; a custom unit avoids
  touching AI/narrative Migrants).
- **Granted at population milestones** to the tall metropolis (there is **NO "per-growth-event"
  trigger** — verified; unit grants are milestone/`run-once`/node-based). MA already has pop tiers
  (T1/T2/T3) — natural milestone anchors. **OPEN: exactly which milestones + how many Surveyors (see §6).**
- Surveyor carries the **`CLAIM_RESOURCE` charged ability** (1 charge, recharge throttle). Walk it to a
  ring-4/5 resource, claim → resource + tile join the metropolis.
- **Tall-gated** (MA's anti-wide gate: full at exactly one settlement per hemisphere).
- **MA per-resource amplifier**: each claimed resource pays the tall city extra (so reaching out is
  worth it). On-theme: a dense metropolis hoards + squeezes resources from a wide radius.

Note on "choice": the resettle-vs-claim choice only existed if we reused the Migrant; with a dedicated
Surveyor the choice is simply when/where to spend it (and which milestones to chase). That's fine.

## 4. Verified mechanics / build recipe (the technical core)

**Claim ability wiring — module breakdown (what to replicate per age):**
- `UNITCOMMAND_CLAIM_RESOURCE` — **base-standard** (all ages, already present ✓).
- Modern-ONLY (must replicate for AQ + EX): `ABILITY_CLAIM_RESOURCE` (Types `KIND_ABILITY`),
  `CHARGED_ABILITY_CLAIM_RESOURCE`, `UnitClass_Abilities` (ability→`UNIT_CLASS_PROSPECTOR`),
  `UnitAbilities` (name/desc), `UnitAbilityModifiers` (ability→grant modifier), `ChargedUnitAbilities`
  (`RechargeTurns`), the grant modifier `…_GRANT_ABILITY_CHARGE`
  (`collection=COLLECTION_OWNER effect=EFFECT_GRANT_UNIT_ABILITY_CHARGE`, args `ChargedAbilityType` +
  `Amount`), and a `TypeTags` row tagging the Surveyor with `UNIT_CLASS_PROSPECTOR`.
- ✅ PROVEN: tagging a unit `UNIT_CLASS_PROSPECTOR` surfaces the claim command (Explorer test, Modern).
  The unit→command link is automatic via the charged ability (the `units.xml` UnitType+Command row is
  just an `AIUnitPrioritizedActions` hint, NOT the grant).

**Granting the Surveyor:**
- `EFFECT_CITY_GRANT_UNIT` (arg `UnitType`) — grants a unit to a city (base game uses it for a
  narrative Migrant gift). Use `run-once` per milestone, tall-gated.
- OR `EFFECT_GRANT_UNIT_OF_CLASS_AND_APPLY_ABILITY` — grants a unit of a class AND applies an ability
  in one effect (Great Person grants use it, `run-once`, node-gated). Lets us grant "a unit carrying
  `ABILITY_CLAIM_RESOURCE`" without pre-tagging a unit type.
- Population-milestone gate: `REQUIREMENT` on city population / MA tier; `run-once` per threshold so it
  doesn't re-fire. (No per-growth trigger exists — verified.)
- ❌ Can't make building it cost a literal population point: Migrant's pop-cost is native + Migrant is
  `CanTrain="false"`; there is **no "on unit trained" trigger** to fire `EFFECT_CITY_ADJUST_POPULATION`.
  The realistic "cost" levers are: production cost, `PrereqPopulation="N"` gate, and the charge cooldown.

**Defining the Surveyor unit:** Types row, `Units` stats row (clone a civilian: `CORE_CLASS_CIVILIAN`,
`UNIT_MOVEMENT_CLASS_FOOT`, ~3 moves), `Unit_Costs` (if buildable), name/desc text, icon, an unlock
(tech/civic node or always-available), tall-gate on production/grant, `TypeTags` → `UNIT_CLASS_PROSPECTOR`.

**MA per-resource amplifier (the payoff):** `EFFECT_CITY_ADJUST_YIELD_PER_RESOURCE` /
`…_PER_SLOTTED_RESOURCE` / `…_PER_AVAILABLE_RESOURCE_TYPE` / `…_PER_RESOURCE_CLASS` — pick one, tall-gated,
so each claimed resource amplifies the metropolis. Wire it through MA's existing per-age attach wrapper
(`MA_AQ_ATTACH_ALL` etc.).

## 5. Build steps (order)

1. **Port the claim ability wiring to AQ + EX** (replicate the Modern-only rows above into MA's
   per-age data; command is already base-standard). RISKIEST piece — nail first; FK errors silently
   drop the mod (validate via Modding.log).
2. **Define the dedicated Surveyor unit** (civilian, tall-gated, `UNIT_CLASS_PROSPECTOR` tag).
3. **Grant it at population milestones** (`EFFECT_CITY_GRANT_UNIT` / `…_OF_CLASS_AND_APPLY_ABILITY`,
   run-once per milestone, tall-gated). Decide milestones (§6).
4. **Add the MA per-resource amplifier** (tall-gated, through the attach wrapper).
5. **Tooltips / LOC strings**, civilopedia, icon.
6. **Fold into Metropolis Ascendant** (generator `tools/gen-ascendant.ps1`), deploy via
   `tools/publish.ps1 -Target game`, in-game test across AQ/EX/MO + a no-DLC load test.
7. **Public roadmap + change-note + Steam/README** (per the standard release workflow).

## 6. OPEN DECISIONS (settle during the build)

- **Which population milestones grant a Surveyor, and how many total?** (e.g., one per MA tier
  T1/T2/T3? every N urban pop? a cap so it's not unlimited?) — Chris to decide; balance lever.
- **Granted-only vs also-buildable** (production) as a second source.
- **Charges + recharge** on the Surveyor (claim throttle) — and whether it's consumed after use.
- **Which per-resource effect + amount** for the amplifier (Deity-balance dial).
- **Reach**: keep native 5 hexes, or also bump `LAND_CLAIM_RANGE_PER_STEP`-style params if relevant
  (note: that param is for the *diplomatic* claim, likely irrelevant here — confirm).

## 7. Reference artifacts (already built, keep)

- **`civ7_mods/mods/claim-resource-test/`** — working reference mod (Modern): tags `UNIT_EXPLORER`
  with `UNIT_CLASS_PROSPECTOR` (proves the claim ability transfers to any unit) + `TEST_DESERT_YIELD`
  per-type yield example (proves per-type yield lands but is uncollected on unworkable tiles). A copy is
  deployed to the game Mods folder — **remove it from the game Mods folder if you don't want the
  Explorer-claim + desert +5 active in normal games before the real build.**
- Full research + every confirmed API: skill `references/tile-ownership-and-radius.md`; memory
  `civ7-tile-swap-and-radius.md`.
