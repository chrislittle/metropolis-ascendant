# Town Specializations → Metropolis Ascendant fold-in map

**Added 2026-06-21.** Goal: a wide empire turns its **towns** into specializations that pipe
benefits to its connected cities. A 1-city tall player has no towns, so gets *none* of this. This doc maps
the entire base-game town-specialization system across AQ/EX/MO and shows how to **internalize each bucket
into the single metropolis** — aligning to the base "buckets" (reuse the same effects + magnitudes) rather
than inventing parallel modifiers, gated on tech/civic/religion nodes like the rest of the fan-out.

Design rule for this workstream: **match the base effect + magnitude, swap the delivery.** Base delivers via a
town project (`TownOnly`, `COLLECTION_OWNER` = a town/city). We deliver the *same effect* via our
`MA_<age>_ATTACH_ALL` wrapper (attached to the **player**), so each modifier uses the **player-rooted
collection** for what it touches (cities / districts / units / plots — see §6), gated by a progression node +
anti-wide. The metropolis "contains the functions of many towns."

> **STATUS: AS-BUILT (refreshed 2026-06-21).** §1–§2 are the base-game reference (unchanged); §3 onward now
> describes what is actually **shipped & deployed**, not the original plan. Naming: this doc sometimes uses
> internal data ids, but the player-facing focus names differ — `PROJECT_TOWN_INN` = **"Hub Town"**,
> `PROJECT_TOWN_TEMPLE` = **"Religious Site"**, `PROJECT_TOWN_PRODUCTION` = **"Mining Town"**.

---

## 1. How town specialization works (base game)

A **Town** (never a City) with population ≥7 builds **one** specialization project at a time
(`ExclusiveSpecialization="true" TownOnly="true" PrereqPopulation="7"`). Each project attaches a modifier
bundle. Two delivery patterns — the distinction is everything for us:

- **Pattern A — "Warehouse" (boosts the town's OWN worked tiles).** Effect
  `EFFECT_CITY_GRANT_WAREHOUSE_YIELD` with named handles (e.g. `AQTownPastureFood`,
  `EXTownMineResourceProduction`). Local tile-yield boosts. → For us: grant to the metropolis → its tiles
  get the boost → **our specialist-adjacency engine then amplifies it.** Stacks with the core mechanic.
- **Pattern B — "...IN_CITY" (sends benefits to CONNECTED cities).** This is the key transferable mechanism.
  The meaningful, transferable effects live here.

Also note `EFFECT_ADJUST_TOWN_CAN_PURCHASE_TAGGED_CONSTRUCTIBLES` appears all over the bundles — it lets a
*town* buy buildings it normally can't. **Irrelevant to us** (a City already builds everything), so we drop
those sub-modifiers from every bucket.

---

## 2. The full bucket catalog (exact effects)

| Bucket | Ages | Pattern | Key effect(s) — exact | Magnitude (base) | Domain |
|---|---|---|---|---|---|
| **Granary** | AQ/EX/MO | A | `EFFECT_CITY_GRANT_WAREHOUSE_YIELD` (food handles) | tile food | Food/Expansionist |
| **Fishing** | AQ/EX/MO | A | `EFFECT_CITY_GRANT_WAREHOUSE_YIELD` (water-tilted food handles) | tile food | Food/Expansionist |
| **Production / Brickyard** | AQ/EX/MO | A | `EFFECT_CITY_GRANT_WAREHOUSE_YIELD` (production handles) | tile production | Military/Production |
| **Trade** | AQ/EX/MO | B | `EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE` ×2 (LAND+SEA), `EFFECT_CITY_GRANT_WAREHOUSE_YIELD` (resource happiness) | **+5 land / +5 sea** range; happiness | Economic |
| **Temple** (Religious Site) | **EX only** | B | `EFFECT_CITY_ADJUST_GREAT_WORK_SLOTS` (BUILDING_TEMPLE), `EFFECT_CITY_ADJUST_CONSTRUCTIBLE_YIELD` (happiness on buildings), `EFFECT_ADJUST_PLAYER_OR_CITY_BUILDING_PURCHASE_EFFICIENCY` | **+2 GW slots**, +2 happiness/bldg, −25% temple cost | Culture / **Religion** |
| **Inn** (Hub Town) | EX/MO | B | `EFFECT_CITY_ADJUST_YIELD_PER_CONNECTED_CITY` (DIPLOMACY) | +1 influence **per connected city** (1/continent) | Diplomatic |
| **Factory** | **MO only** | B | `EFFECT_CITY_ADJUST_RESOURCE_CAP`, `EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE` ×2, `EFFECT_ADJUST_PLAYER_OR_CITY_BUILDING_PURCHASE_EFFICIENCY` (Factory/Port/Rail) | **+1 resource cap**, +5/+5 range, 100% discounts | Economic |
| **Fort** | all ages (base-standard) | B | `EFFECT_UNIT_ADJUST_HEAL_PER_TURN` (near city), `EFFECT_DISTRICT_ADJUST_TOTAL_HEALTH`, `EFFECT_PLOT_ADJUST_YIELD` (gold on fortifications) | +5 heal, **+25 district health**, +1 gold | Military (defense) |
| **Urban Center** | all ages (base-standard) | B | `EFFECT_PLOT_ADJUST_YIELD` on `REQUIREMENT_PLOT_IS_QUARTER` | **+1 Science & +1 Culture per quarter** | Science + Culture |
| **Resort** | all ages (base-standard) | B | `EFFECT_PLOT_ADJUST_YIELD` (appeal tiles), `EFFECT_PLOT_ADJUST_YIELD` (natural wonder) | +1 gold/happiness on appeal tiles; **+50% NW tile yields** | Happiness / Culture |

Source files: `base-standard/data/projects.xml` + `projects-gameeffects.xml` (Fort/Urban Center/Resort);
`age-{antiquity,exploration,modern}/data/projects.xml` + `projects-gameeffects.xml` (the rest).

---

## 3. As-built roll-in (shipped + deployed)

Final policy: **roll in a bucket only for a mechanic the fan-out kit doesn't already grant** — never
stack a duplicate yield source. Warehouse tile-boosts count as *distinct* from the flat under-settlement-cap
Food/Production (a per-tile boost vs a player yield), so they're in. The town-spec roll-in is a **layer
distinct from the Suzerain layer** — emitted in its own `TOWN-SPECIALIZATION ROLL-IN` block in
`gen-ascendant.ps1`, separate from the `SUZERAIN LAYER` block. Built for **Antiquity + Exploration + Modern**
(Modern ported 2026-06-22, minus the religion bucket — see §3 Modern). Every bucket carries the **tall
(one-city-per-hemisphere) anti-wide gate** — off at the next settlement (AQ: more than 1; EX/MO: more than 2),
matching the core kit's SOLO cutoff (tightened from the old `<4` gate 2026-06-22).

### Antiquity
| Bucket (focus name) | Effect as built | Node gate | Magnitude |
|---|---|---|---|
| Hub Town | +Influence on the Monument (`EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD`) | `NODE_TECH_AQ_MASONRY` | +3 |
| Fort Town | district HP + unit heal + gold on fortifications | `NODE_TECH_AQ_MILITARY_TRAINING` | +25 HP / +5 heal / +1 gold |
| Farming/Fishing | warehouse Food on rural tiles | `NODE_TECH_AQ_IRRIGATION` (FoodCap) | base handles |
| Mining | warehouse Production on rural tiles | `NODE_TECH_AQ_BRONZE_WORKING` (ProdCap) | base handles |
| Trade Outpost | resource-Happiness warehouse | `NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS` | — |
| Trade Outpost (range) | +trade-route range land+sea (`M-TradeRange`) | Code of Laws | **+5 / age** |
| Resort | appeal Gold/Happiness + 50% Natural-Wonder tile yields | `NODE_TECH_AQ_MASONRY` **mastery (depth 2)** | +1 / +50% |

### Exploration (adds the religion bucket)
| Bucket (focus name) | Effect as built | Node gate | Magnitude |
|---|---|---|---|
| Hub Town | +Influence on the Guildhall | `NODE_TECH_EX_GUILDS` | +3 |
| Fort Town | district HP + unit heal + gold on fortifications | `NODE_TECH_EX_HERALDRY` | +25 / +5 / +1 |
| Farming/Fishing | warehouse Food on rural tiles | `NODE_TECH_EX_FEUDALISM` (FoodCap) | base handles |
| Mining | warehouse Production on rural tiles | `NODE_TECH_EX_MACHINERY` (ProdCap) | base handles |
| Trade Outpost | resource-Happiness warehouse + range | `NODE_TECH_EX_CARTOGRAPHY` | +5 / age |
| **Religious Site** | +2 ANY GW slots on Temples (relics) **and** +2 Happiness/Building | `NODE_CIVIC_EX_BRANCH_THEOLOGY` | +2 / +2 |
| Resort | appeal + 50% Natural-Wonder tile yields | `NODE_TECH_EX_CASTLES` **mastery (depth 2)** | +1 / +50% |

### Modern (fan-out ported 2026-06-22; religion bucket intentionally absent)
| Bucket (focus name) | Effect as built | Node gate | Magnitude |
|---|---|---|---|
| Hub Town | +Influence on the Opera House | `NODE_TECH_MO_URBANIZATION` | +3 |
| Fort Town | district HP + unit heal + gold on fortifications | `NODE_TECH_MO_MILITARY_SCIENCE` | +25 / +5 / +1 |
| Farming/Fishing | warehouse Food on rural tiles (`MOTown*Food`) | `NODE_TECH_MO_MASS_PRODUCTION` (FoodCap) | base handles |
| Mining | warehouse Production on rural tiles (`MOTown*Production`) | `NODE_TECH_MO_INDUSTRIALIZATION` (ProdCap) | base handles |
| Trade Outpost | resource-Happiness warehouse + range | `NODE_TECH_MO_COMBUSTION` | +5 / age |
| Resort | appeal + 50% Natural-Wonder tile yields | `NODE_TECH_MO_STEAM_ENGINE` **mastery (depth 2)** | +1 / +50% |

> **No Religious Site bucket in Modern** — Civ VII religion/relics are an Exploration-age system; Modern has no
> religion node and no relic accrual, so the Temple GW-slot bucket *and* the relic/Great-Work culture amplifier
> both stay EX-only by design.

Total modifier counts after the full roll-in + node split: **AQ 75 / EX 115 / MO 109**.

---

## 4. Key design decisions (final)

- **Influence is player-level — never per-pop.** Hub influence is a flat
  `EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD` on the age's Diplomacy building (Monument / Guildhall), gated
  behind that building's unlock node. (An early per-pop attempt was wrong — `EFFECT_CITY_ADJUST_YIELD_PER_
  POPULATION` does not emit `YIELD_DIPLOMACY`; the skill's city-states ref already warned this.) It is the
  influence **floor** that the Suzerain per-suzerain layer + primer compound — fixing the Deity "+5 influence"
  cap that made the suzerain plan a paper layer.
- **Distinct from the Suzerain layer** in both code (separate emit block) and skills (separate references).
- **Overlap avoided.** Trade-route **range** and Factory **resource cap** were already MA levers
  (`M-TradeRange`, `M-ResourceCap`) — NOT re-emitted as town buckets. Warehouses power up **rural tiles** (a
  distinct mechanic), so they coexist with the flat under-cap Food/Production rather than double-counting.
- **Node de-loading (the split).** Fort and Resort were moved off the overloaded Org Military/Authority and
  Masonry/Castles first-tier nodes: **Fort → its own military tech** (Military Training / Heraldry), **Resort →
  the wonder node's mastery (depth 2)**. Org Military/Authority now carry only combat strength; Masonry/Castles
  depth-1 carry only wonder-%.
- **Resort & Natural Wonders.** No "city near a Natural Wonder" requirement exists, so the +50% effect
  **self-targets NW tiles** — it only pays out if the city actually has one nearby. That satisfies "all the
  benefits if near a natural wonder."
- **Trade range = +5 per age** rather than a fixed distance — each age's lever grants +5.

---

## 5. Deferred / not built

- **Factory Town gold-discount** (Factory/Port/Rail purchase efficiency,
  `EFFECT_ADJUST_PLAYER_OR_CITY_BUILDING_PURCHASE_EFFICIENCY`) — STILL NOT BUILT in any age (it is a distinct
  purchase-efficiency effect, never wired through the attach wrapper). MA's resource-cap already covers Factory's
  *resource slots* (the main Factory value); the gold-discount is the minor remainder. The MO fan-out is now done
  WITHOUT it — add it later as its own bucket if a Modern playtest shows purchase economy matters (verify the
  effect fires through the `COLLECTION_MAJOR_PLAYERS` wrapper first).
- **All Modern town-spec** — ✅ DONE 2026-06-22 (Hub/Fort/Farming/Mining/Trade/Resort ported; see §3 Modern). Only
  the Factory gold-discount above and the (never-built) Urban Center remain.
- **Urban Center** (+1 Science & Culture per Quarter) — skipped; overlaps the existing Science/Culture kit.
- **Religious Site's −25% temple purchase discount** — not built (minor; the slots + happiness are the value).

---

## 6. Implementation reference (`tools/gen-ascendant.ps1`)

- **Builders:** `M-HubInfluence`; `M-FortHealth` / `M-FortHealing` + `M-PlotYield` (Fort gold); `M-Warehouse`
  (food / prod / happiness, from the `$warehouse` handle table); `M-BuildingHappiness` (Religious Site
  happiness); `M-TempleSlots` (relic slots); `M-PlotYield` (Resort appeal + NW).
- **Player-rooted collections** (verified to deliver through the `COLLECTION_MAJOR_PLAYERS` attach wrapper —
  use these, NOT the city/unit/plot-context variants which silently no-op): warehouse →
  `COLLECTION_PLAYER_CITIES`; district HP → `COLLECTION_PLAYER_DISTRICTS`; unit heal →
  `COLLECTION_PLAYER_UNITS`; plot yield → `COLLECTION_PLAYER_PLOT_YIELDS`; per-building →
  `COLLECTION_OWNER` + `EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD` (`ConstructibleClass=BUILDING`). (Also folded
  into the civ7-modding skill's gameeffects ref.)
- **Mastery gating:** `OwnerNodeAntiWide` / `M-PlotYield` take a `$minDepth` param; Resort passes
  `MinDepth=2`. `MinDepth=2` only fires on a node that HAS a depth-2 mastery (Masonry & Castles do — verified
  via `UnlockDepth="2"` rows); gate a node without one and it silently never fires.
- **Discoverability of mastery bonuses (2026-06-22):** the Resort note is its own `RESORT` note Key with
  `Depth=2` in the `$ages` Notes array, so it renders on the node's **Mastery** panel (matching where the bonus
  actually unlocks) instead of being folded into the depth-1 `CULTURE` (wonder-%) note. `traditions.xml` is now
  **fully generated** from the Notes array (GameModifiers binding + ProgressionTreeNodeUnlocks, with each note's
  `Depth` → `UnlockDepth`) — no more 3-way hand-sync of marker / text / unlock-row. Note text dropped the
  town-bonus labels (no more "(Mining Town)", "Resort:", "(Fort Town)", etc.); each note plainly describes the
  effect.
- **Tuning vars:** `$hubInfluenceAmt` (3), `$fortHealth`/`$fortHeal`/`$fortGold` (25/5/1), `$religiousHappy`
  (2), `$resortAppeal`/`$resortNWPercent` (1/50), `$age.TradeRange` (5), the `$warehouse` handle table.
- Discoverability notes are auto-generated; new `FORT` note added; the Military note no longer mentions Fort.
