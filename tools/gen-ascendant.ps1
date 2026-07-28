# =====================================================================================
# Metropolis Ascendant - base-node modifiers generator (2026-06-18; retired-system cleanup 2026-07-24)
# =====================================================================================
# Emits each age's data/<age>/modifiers.xml IN FULL from the $ages config table below -
# deterministic, self-validating (parses the result as XML), and easy to retune. This script owns
# the WHOLE base-node file; the Ascendancy tree (the play-driven progression that owns most Gen-2
# bonuses) is generated separately by gen-ascendancy.ps1 and run after this one.
#
# WHAT SHIPS FROM HERE (per age):
#   - The two TIER-1 SAFETY NETS, per hemisphere: -50% specialist Food+Happiness upkeep (applies
#     only while the city is below Ecstatic) and a flat Happiness bonus. These count CITIES ONLY
#     (OnlyCities=true) and are UNGATED (no tech node) - a safety valve that must never be revoked
#     by growing a town, or placed specialists would strand into the over-cap unhappiness spiral.
#     (Their anti-wide guard is a per-hemisphere <5-cities threshold - see GitHub #25, which
#     proposes moving them onto the earned-allowance gate like everything else.)
#   - THE GEN-2 PILLAR FAMILY (emitted once, non-DL): the tall engine - Arcadia rural ring / peaks /
#     waters, the coastal floor, wonder-happiness + mountain + water adjacency, wonder appeal, and
#     the mountain/ocean workability unlocks. Two gate shapes:
#       * WINDOWED on the EARNED ALLOWANCE (yields): count windows re-evaluate live in-leaf; some
#         copies ride ATTACH_ALL, some attach via the age's Expansion FEAT reward (the only proven
#         mid-session Triumph delivery). See PillarWindows / $tallCap.
#       * STRUCTURAL (capacity/activation/adjacency, binary): ONE copy, count ceiling = the age max,
#         NEVER windowed - a windowed activation effect processes its OFF before its ON at a count
#         change and evicts (the run-5 Temple-slot bug dropped 4 relics that way). See $structWin.
#   - The player-wide once-per-age lanes: the SUZERAIN layer (per-pop yield per suzerained CS type,
#     + diplo + primer + trade range + resource cap), the RAZING layer (capture Gold/Influence lump,
#     faster burn, pillage plunder), the SURVEYOR claim-charge grant (AQ/EX), and the MODERN
#     victory-wonder RECYCLE convert modifiers.
#   - The ATTACH_ALL delivery wrapper (COLLECTION_MAJOR_PLAYERS + EFFECT_ATTACH_MODIFIERS) that
#     traditions.xml binds, so every modifier above resolves its own collection/node/pop/anti-wide gate.
#
# HEMISPHERE SCOPING (the safety nets only): Antiquity (Distant=$false) has no Distant Lands, so it
# emits ONE unscoped set. Exploration / Modern (Distant=$true) emit a HOMELAND set (city req
# REQUIREMENT_CITY_IS_DISTANT_LANDS inverse + OnlyHomelands=true) AND a DISTANT-LANDS set (_DL ids;
# the req without inverse + OnlyDistantlands=true). NB the base-game spelling "OnlyDistantlands"
# (lowercase L) - the capitalised form silently never fires.
#
# GATES: node-gated rewards carry an OwnerRequirements gate on the host TECH NODE
# (REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE + MinDepth=1 - the MinDepth child is
# REQUIRED or it silently never fires). The safety nets are intentionally UNGATED.
#
# HISTORY: this generator once also emitted a large v1 bonus set (specialist caps, resource caps,
# per-pop rungs, wonder %, the trade kit, town-specialization buckets) under a per-hemisphere
# GEOMETRIC taper (SOLO/COMPACT/QUARTER bands). Gen-2 moved all of it onto the Ascendancy tree and
# the taper collapsed to a single band; the dead code + its stale scaffolding were deleted
# 2026-07-24 (issue #22). To read the pre-Gen-2 generator, use the export repo's git history.
#
# RE-RUNNABLE + DETERMINISTIC: re-running with unchanged config reproduces the files byte-for-byte.
param([switch]$Test)   # -Test emits the throwaway metropolis-ascendant-test mod (low pop thresholds 2/4/6 + tech gate removed) for fast in-game validation
$ErrorActionPreference = 'Stop'
# pwsh 7+ ONLY: Windows PowerShell 5.1 misreads this script's / the synced files' UTF-8 (no BOM) as ANSI and
# double-encodes em-dashes on write (proven 2026-07-04: corrupted README/modinfo/TREE-DEPTH-MAP). Hard stop.
if ($PSVersionTable.PSVersion.Major -lt 7) { throw "gen-ascendant.ps1 requires PowerShell 7+ (pwsh). Windows PowerShell 5.1 corrupts UTF-8 text on write. Run: pwsh -File tools\gen-ascendant.ps1 (or '& tools\gen-ascendant.ps1' from a pwsh session)." }
$TestMode = $Test.IsPresent

# ============ GEN-2 MIGRATION (2026-07-11; v1 copies DELETED 2026-07-24, issue #22) ============
# The Ascendancy tree (tools/gen-ascendancy.ps1) owns the migrated bonuses per the GEN2-CONTENTS
# migration map: T3 per-pop rungs (Sci/Cul/Prod), the Joyous/Ecstatic stage escalators, Wonder-
# production %, Great Work slots (Palace + per-building + EX Temples), and the trade kit
# (routes/range/resource-Happiness). Their v1 copies used to be suppressed at runtime by a
# $Gen2Strip flag; the flag was pinned on for the whole Gen-2 release, so the dead branches were
# deleted outright. To read the pre-Gen-2 generator or its output, use the export repo's git
# history (any commit before "Gen2 release") - the flag was never a working rollback on its own,
# because gen-ascendancy.ps1 still emitted the tree alongside it.
# Full-strip note keys (their whole bonus migrated to the Ascendancy tree). The Build-NoteText
# rewording of SCIENCE/CULTURE2 (adjacency-half kept) is now OBSOLETE: A1 (2026-07-14) moved the
# Science/Culture adjacency onto the Ascendancy tree too, so those halves no longer live on base.
$gen2StrippedNoteKeys = @('SCIENCE2','STAGE_SCIENCE','STAGE_CULTURE','TRADE','MILITARY','CULTURE',
                          'RESORT','FOODCAP','PRODCAP',   # A2 de-layer 2026-07-14: suppress base-node panel text for the dropped Resort + Warehouse Food/Prod bonuses
                          'FORT',                          # A2 2026-07-14: orphan cleanup - Fort modifiers were retired 2026-07-13 (-> Musters/MIL1) but their base-node ad was left behind
                          'RELIGION',                      # A3 2026-07-14: Religious Site bucket consolidated into Great Patrons (GW slots + relic-Culture) / happiness dropped; base Theology node -> vanilla
                          'SCIENCE','CULTURE2','ECONOMIC','ECONOMIC2','MILITARY2',   # A4 sweep 2026-07-14 (Chris): stale v1 T1/T2/T3 notes - adjacency->Ascendancy (A1), specialist slots/resource cap/combat strength all migrated off base.
                          'SUZERAIN')                      # 2026-07-14 (Chris): base civic tree must be fully VANILLA. The suzerain mechanic is explained by the dashboard Protectorates panel instead (no base-node note). Yields still fire (always-on modifiers).

# A1 adjacency port (2026-07-14): ALL 7 base-node-gated adjacency rules moved off the base tech/civic
# tree. The 5 Science/Culture rules -> Ascendancy SCI1/SCI2/CUL1/CUL2/REP1 (amplify base rules). The 2
# Per age: suffix, age/tech display names, host tech node, the tier population gates, the flat Happiness
# safety amount, and whether Distant Lands exist (EX/MO yes).
# ⚠ VESTIGIAL FIELDS (issue #22 follow-up): several reward-magnitude fields in the $ages table below -
# Wonders (wonder-% band values), GW (Palace Great-Work slots), Collection (per-building slot amount),
# ResCap, Trade, MilStrength, UnderCapAmount, TradeRange, HubNode/HubBuilding, FortNode - fed the v1
# bonus loops that Gen-2 migrated to the Ascendancy tree. Those loops were deleted 2026-07-24, but the
# fields were LEFT IN PLACE because they are NOT fully dead: Build-NoteText still reads most of them (its
# note strings are skipped at emit, so shipped DATA is unaffected), and the TREE-DEPTH-MAP.md generator
# still reads HubNode/FortNode and writes rows for the RETIRED Hub/Fort/Resort bonuses into that dev doc.
# Removing the fields therefore requires cleaning Build-NoteText + the TREE-DEPTH-MAP generator too - a
# focused pass, not a config-only delete. Not output-neutral (TREE-DEPTH-MAP.md changes).
# FAN-OUT MODEL (Metropolis Ascendant): instead of every bonus gating on one host tech per age, each
# modifier family carries a DOMAIN gate node. `Nodes` maps domain -> tree node. In ANTIQUITY the domains
# are spread across real tech/civic nodes (the experiment); EXPLORATION/MODERN keep ALL domains on the old
# single host node (v3 behaviour) until the fan-out is ported there (ROADMAP Phase 4). Additive per node:
# each node lights its own slice. Domains: Spine=specialist worker-cap; Science/ScienceDeep; Culture;
# Economic; Military (new). `FanOut=$true` enables the new AQ-only families (military production per pop,
# Qajar-style early Food/Production, economic trade-route RANGE). The safety nets stay UNGATED (always-on).
$ages = @(
    @{ Key='antiquity';   Sfx='AQ'; AgeName='Antiquity';   Node='NODE_TECH_AQ_CURRENCY';    TechName='Currency'; BonusAge='ANTIQUITY';
       Pops=@(5,9,12);   Happiness=10; Preserve=1; MtnDedup=$true; Wonders=@(20,10,5); GW=3; Collection=2; ResCap=@(2,2,2); Trade=2; Distant=$false;
       FanOut=$true; MilProd=1; UnderCapAmount=2; TradeRange=5; MilStrength=3;
       HubBuilding='BUILDING_MONUMENT'; HubNode='NODE_TECH_AQ_MASONRY';   # Hub Town bucket: +Influence on the Monument (yields Influence), gated behind Masonry
       FortNode='NODE_TECH_AQ_MILITARY_TRAINING';   # Fort Town bucket gets its OWN node (off Org Military, which was overloaded)
       Nodes=@{ Spine='NODE_TECH_AQ_CURRENCY';
                Science='NODE_TECH_AQ_WRITING';        ScienceDeep='NODE_TECH_AQ_WRITING';        # front-load 2026-06-22: science per-pop Literacy(col5)->Writing(consolidate on the science node)
                Culture='NODE_CIVIC_AQ_MAIN_MYSTICISM'; CultureDeep='NODE_CIVIC_AQ_MAIN_MYSTICISM'; Wonders='NODE_TECH_AQ_MASONRY';
                Economic='NODE_TECH_AQ_CURRENCY';      EconomicDeep='NODE_TECH_AQ_WHEEL';        Commerce='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS';   # front-load: ResCap-T3 Skilled Trades(col5)->Wheel; Trade Commerce(col6)->Code of Laws
                Military='NODE_TECH_AQ_BRONZE_WORKING'; MilitaryDeep='NODE_CIVIC_AQ_MAIN_ORG_MILITARY';   # Combat stays on Org Military (2026-06-22)
                FoodCap='NODE_TECH_AQ_IRRIGATION';     ProdCap='NODE_TECH_AQ_BRONZE_WORKING';    # front-load: under-cap Prod Engineering(col5)->Bronze Working
                Diplomatic='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS' };   # Suzerain layer: governance/laws as the AQ diplomatic home (col2)
       Notes=@(
         @{ Node='NODE_TECH_AQ_WRITING';              Key='SCIENCE'  }
         @{ Node='NODE_TECH_AQ_WRITING';              Key='SCIENCE2' }   # moved off Literacy (col5) onto Writing
         @{ Node='NODE_TECH_AQ_WRITING';              Key='STAGE_SCIENCE' }   # IDEA 1: happiness-stage Science payoff
         @{ Node='NODE_TECH_AQ_MASONRY';              Key='CULTURE'  }
         @{ Node='NODE_TECH_AQ_MASONRY';              Key='RESORT'; Depth=2 }   # mastery-gated (MinDepth=2) -> shows on the node's MASTERY panel
         @{ Node='NODE_CIVIC_AQ_MAIN_MYSTICISM';      Key='CULTURE2' }
         @{ Node='NODE_CIVIC_AQ_MAIN_MYSTICISM';      Key='STAGE_CULTURE' }   # IDEA 1: happiness-stage Culture payoff
         @{ Node='NODE_TECH_AQ_CURRENCY';             Key='ECONOMIC' }
         # (Surveyor note removed 2026-07-02: the unit has no unlock on Currency and no gated bonus - it's buildable from
         #  turn 1 and self-documents in the build list, so a Currency-node note wrongly implied an unlock. See issue #12.)
         @{ Node='NODE_TECH_AQ_WHEEL';                Key='ECONOMIC2'}   # moved off Skilled Trades (col5) onto Wheel
         @{ Node='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS';   Key='TRADE'    }   # moved off Commerce (col6) onto Code of Laws (shares with Suzerain note)
         @{ Node='NODE_TECH_AQ_BRONZE_WORKING';       Key='MILITARY' }
         @{ Node='NODE_CIVIC_AQ_MAIN_ORG_MILITARY';   Key='MILITARY2'}
         @{ Node='NODE_TECH_AQ_MILITARY_TRAINING';    Key='FORT'     }
         @{ Node='NODE_TECH_AQ_IRRIGATION';           Key='FOODCAP'  }
         @{ Node='NODE_TECH_AQ_BRONZE_WORKING';       Key='PRODCAP'  }   # moved off Engineering (col5) onto Bronze Working (shares with Military prod)
         @{ Node='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS';   Key='SUZERAIN' } ) }
    @{ Key='exploration'; Sfx='EX'; AgeName='Exploration'; Node='NODE_TECH_EX_EDUCATION';   TechName='Education'; BonusAge='EXPLORATION';
       Pops=@(8,14,20);  Happiness=12; Preserve=2; Wonders=@(25,13,6); GW=3; Collection=2; ResCap=@(2,2,2); Trade=2; Distant=$true;
       FanOut=$true; MilProd=1; UnderCapAmount=2; TradeRange=5; MilStrength=3; TempleSlots=2;   # TempleSlots = town-spec "Religious Site" bucket, EX-only (relic storage), gated on the religion node
       HubBuilding='BUILDING_GUILDHALL'; HubNode='NODE_TECH_EX_GUILDS';   # Hub Town bucket: +Influence on the Guildhall (+6 Influence building), gated behind Guilds
       FortNode='NODE_TECH_EX_HERALDRY';   # Fort Town bucket gets its OWN node (off Authority, which was overloaded)
       # FAN-OUT PORT (Phase 4, 2026-06-20; REBALANCED for tree-depth from the EX trees). Domains
       # spread across real EX tech/civic nodes, mirroring the AQ structure (Spine+Economic share one node so
       # the specialist+rescap note stays accurate; big science block on a tech, big culture block on a civic).
       # TIMING-AWARE: tech cols 1=Machinery/Astronomy/Cartography, 2=Castles/Heraldry/Feudalism/Guilds,
       # 3=Metallurgy/Shipbuilding/Education, 4=MetalCasting/Architecture, 5=Gunpowder/UrbanPlanning(END).
       # Civic cols 1=Piety/Economics, 2=Inspiration/Authority/Mercantilism, 3=Society/DiploService/Bureaucracy/
       # Colonialism, 4=SocialClass/Sovereignty/Imperialism. The density SPINE is on GUILDS (col2, was wrongly on
       # URBAN_PLANNING = col5/end-of-age); early engines (Science=Astronomy, Commerce=Cartography, ProdCap=
       # Machinery) are col1. Culture lane on PIETY (col1, the earliest culture/religion civic) MIRRORS AQ's
       # Culture-on-Mysticism and gets the all-age adjacency block online a column earlier. RELIGION MECHANICS
       # still untouched (relics/faith/tourism) - Piety here is just a GATE node, not the religion lane (TODO).
       Nodes=@{ Spine='NODE_TECH_EX_GUILDS';
                Science='NODE_TECH_EX_ASTRONOMY';          ScienceDeep='NODE_TECH_EX_ASTRONOMY';   # front-load 2026-06-22: science per-pop Education(col3)->Astronomy (consolidate on the science node, mirrors AQ Writing)
                Culture='NODE_CIVIC_EX_MAIN_PIETY';        CultureDeep='NODE_CIVIC_EX_MAIN_PIETY';       Wonders='NODE_TECH_EX_CASTLES';
                Economic='NODE_TECH_EX_GUILDS';            EconomicDeep='NODE_CIVIC_EX_MAIN_MERCANTILISM'; Commerce='NODE_TECH_EX_CARTOGRAPHY';
                Military='NODE_TECH_EX_METALLURGY';        MilitaryDeep='NODE_CIVIC_EX_MAIN_AUTHORITY';
                FoodCap='NODE_TECH_EX_FEUDALISM';          ProdCap='NODE_TECH_EX_MACHINERY';
                Religion='NODE_CIVIC_EX_BRANCH_THEOLOGY';  # town-spec "Temple" bucket: relic/Great-Work slots on the religion-branch civic (engages the under-used civic tree)
                Diplomatic='NODE_CIVIC_EX_MAIN_DIPLOMATIC_SERVICE' };   # Suzerain layer + Inn influence floor: literal Diplomatic Service civic (col3)
       Notes=@(
         @{ Node='NODE_TECH_EX_ASTRONOMY';          Key='SCIENCE'  }
         @{ Node='NODE_TECH_EX_ASTRONOMY';          Key='SCIENCE2' }   # moved off Education (col3) onto Astronomy (consolidate science)
         @{ Node='NODE_TECH_EX_ASTRONOMY';          Key='STAGE_SCIENCE' }   # IDEA 1: happiness-stage Science payoff
         @{ Node='NODE_TECH_EX_CASTLES';            Key='CULTURE'  }
         @{ Node='NODE_TECH_EX_CASTLES';            Key='RESORT'; Depth=2 }   # mastery-gated (MinDepth=2) -> shows on the node's MASTERY panel
         @{ Node='NODE_CIVIC_EX_MAIN_PIETY';        Key='CULTURE2' }
         @{ Node='NODE_CIVIC_EX_MAIN_PIETY';        Key='STAGE_CULTURE' }   # IDEA 1: happiness-stage Culture payoff
         @{ Node='NODE_TECH_EX_GUILDS';             Key='ECONOMIC' }
         # (Surveyor note removed 2026-07-02 - buildable from turn 1, no unlock/gated bonus; see issue #12.)
         @{ Node='NODE_CIVIC_EX_MAIN_MERCANTILISM'; Key='ECONOMIC2'}
         @{ Node='NODE_TECH_EX_CARTOGRAPHY';        Key='TRADE'    }
         @{ Node='NODE_TECH_EX_METALLURGY';         Key='MILITARY' }
         @{ Node='NODE_CIVIC_EX_MAIN_AUTHORITY';    Key='MILITARY2'}
         @{ Node='NODE_TECH_EX_HERALDRY';           Key='FORT'     }
         @{ Node='NODE_TECH_EX_FEUDALISM';          Key='FOODCAP'  }
         @{ Node='NODE_TECH_EX_MACHINERY';          Key='PRODCAP'  }
         @{ Node='NODE_CIVIC_EX_BRANCH_THEOLOGY';   Key='RELIGION' }
         @{ Node='NODE_CIVIC_EX_MAIN_DIPLOMATIC_SERVICE'; Key='SUZERAIN' } ) }
    @{ Key='modern';      Sfx='MO'; AgeName='Modern';      Node='NODE_TECH_MO_ELECTRICITY'; TechName='Electricity'; BonusAge='MODERN';
       Pops=@(10,16,24); Happiness=15; Preserve=3; Wonders=@(30,15,8); GW=4; Collection=3; ResCap=@(3,3,3); Trade=3; Distant=$true;
       FanOut=$true; MilProd=1; UnderCapAmount=2; TradeRange=5; MilStrength=3;   # NO TempleSlots: Modern has no religion/relic system, so the Temple/relic buckets + GW-culture amp stay EX-only by design
       HubBuilding='BUILDING_OPERA_HOUSE'; HubNode='NODE_TECH_MO_URBANIZATION';  # Hub Town bucket: +Influence on the Opera House (yields Influence), gated behind Urbanization (its unlock node)
       FortNode='NODE_TECH_MO_MILITARY_SCIENCE';   # Fort Town bucket on its own military node (Defensive Fortifications/Military Academy unlock here)
       # FAN-OUT PORT (Phase 4 MODERN, 2026-06-22). Domains spread across real MO tech/civic nodes, mirroring AQ/EX
       # and TIMING-AWARE via UILayoutColumn (techs) / Cost (civics). The specialist SPINE = Electricity (col3) -
       # the base game's own specialist-cap-increase node (MOD_MO_SPECIALIST_CAP_INCREASE), so density + rescap sit
       # where the cap actually lives. TECH cols: 2=Academics; 3=Electricity/Urbanization/Aerodynamics/Flight/Rocketry;
       # 4=Steam Engine; 5=Combustion/Industrialization/Mass Production/Mobilization/Nuclear Fission; 6=Military Science;
       # 7=Armor/Computation/Radio. CIVIC main-tree has no columns (cost-ordered): 1600=Modernization/Natural History/
       # Social Question; 2750=Political Theory; 3750=Globalism/Nationalism; 7500=Capitalism/Hegemony/Militarism.
       # Wonders -> Steam Engine (industry; HAS a depth-2 mastery so Resort lands on its Mastery panel). Culture lane
       # on Natural History (earliest culture civic, mirrors AQ Mysticism / EX Piety). Suzerain/Diplomatic on Globalism
       # (international diplomacy). Combat on Nationalism (earlier than the 7500 Militarism). Food on Mass Production
       # (Cannery = food), Production on Industrialization (rail/industry). Religion lane intentionally absent.
       Nodes=@{ Spine='NODE_TECH_MO_ELECTRICITY';
                Science='NODE_TECH_MO_ACADEMICS';          ScienceDeep='NODE_TECH_MO_ACADEMICS';   # front-load 2026-06-22: science per-pop Computation(col4)->Academics (consolidate)
                Culture='NODE_CIVIC_MO_MAIN_NATURAL_HISTORY'; CultureDeep='NODE_CIVIC_MO_MAIN_NATURAL_HISTORY'; Wonders='NODE_TECH_MO_STEAM_ENGINE';
                Economic='NODE_TECH_MO_ELECTRICITY';        EconomicDeep='NODE_TECH_MO_ELECTRICITY'; Commerce='NODE_TECH_MO_COMBUSTION';   # front-load: ResCap-T3 Capitalism(col4)->Electricity (consolidate)
                Military='NODE_TECH_MO_MILITARY_SCIENCE';   MilitaryDeep='NODE_CIVIC_MO_MAIN_NATIONALISM';   # front-load: prod-per-pop Mobilization(col4)->Military Science (consolidate w/ Fort)
                FoodCap='NODE_TECH_MO_MASS_PRODUCTION';     ProdCap='NODE_TECH_MO_INDUSTRIALIZATION';
                Diplomatic='NODE_CIVIC_MO_MAIN_GLOBALISM' };   # Suzerain layer: Globalism as the MO diplomatic home
       Notes=@(
         @{ Node='NODE_TECH_MO_ACADEMICS';             Key='SCIENCE'  }
         @{ Node='NODE_TECH_MO_ACADEMICS';             Key='SCIENCE2' }   # moved off Computation (col4) onto Academics (consolidate science)
         @{ Node='NODE_TECH_MO_ACADEMICS';             Key='STAGE_SCIENCE' }   # IDEA 1: happiness-stage Science payoff
         @{ Node='NODE_TECH_MO_STEAM_ENGINE';          Key='CULTURE'  }
         @{ Node='NODE_TECH_MO_STEAM_ENGINE';          Key='RESORT'; Depth=2 }   # mastery-gated (MinDepth=2) -> shows on the node's MASTERY panel
         @{ Node='NODE_CIVIC_MO_MAIN_NATURAL_HISTORY'; Key='CULTURE2' }
         @{ Node='NODE_CIVIC_MO_MAIN_NATURAL_HISTORY'; Key='STAGE_CULTURE' }   # IDEA 1: happiness-stage Culture payoff
         @{ Node='NODE_TECH_MO_ELECTRICITY';           Key='ECONOMIC' }
         # (Surveyor note removed 2026-07-02 - buildable from turn 1, no unlock/gated bonus; see issue #12.)
         @{ Node='NODE_TECH_MO_ELECTRICITY';           Key='ECONOMIC2'}   # moved off Capitalism (col4) onto Electricity (consolidate resource cap)
         @{ Node='NODE_TECH_MO_COMBUSTION';            Key='TRADE'    }
         @{ Node='NODE_TECH_MO_MILITARY_SCIENCE';      Key='MILITARY' }   # moved off Mobilization (col4) onto Military Science (consolidate w/ Fort)
         @{ Node='NODE_CIVIC_MO_MAIN_NATIONALISM';     Key='MILITARY2'}
         @{ Node='NODE_TECH_MO_MILITARY_SCIENCE';      Key='FORT'     }
         @{ Node='NODE_TECH_MO_MASS_PRODUCTION';       Key='FOODCAP'  }
         @{ Node='NODE_TECH_MO_INDUSTRIALIZATION';     Key='PRODCAP'  }
         @{ Node='NODE_CIVIC_MO_MAIN_GLOBALISM';       Key='SUZERAIN' } ) }
)
if ($TestMode) { foreach ($a in $ages) { $a.Pops = @(2,4,6) } }   # tiny thresholds so all 3 tiers fire at low pop

# The Civ VII version you have TESTED on. Injected into the modinfo <Description> + the mod README so the
# player-facing "tested on" string is single-sourced. Bump this when you re-validate on a newer patch.
$testedVersion = '1.4.2'

# SUZERAIN LAYER (Phase 3, ROUTE A). Five CITY-yield types -> PER-POP yield, each unlocked by drafting that
# type's Shareable CS bonus (id CITY_STATE_<TYPE>_BONUS_<BonusAge>_7). DIPLOMATIC->Influence + free POP +
# primer handled separately. All scale with POPULATION (the only axis a one-city tall player has).
$suzCity = [ordered]@{
    SCIENTIFIC   = 'YIELD_SCIENCE'
    CULTURAL     = 'YIELD_CULTURE'
    MILITARISTIC = 'YIELD_PRODUCTION'
    ECONOMIC     = 'YIELD_GOLD'
    EXPANSIONIST = 'YIELD_FOOD'
}
$suzPerPopDiv = 4  # per-pop divisor for suzerain yields: +1 yield per 4 Urban Pop (stacks on the node per-pop).
                   # GEN-2 DECOUPLE (Chris 2026-07-13): was 3, gated on the Shareable-bonus pick; now the stream
                   # flows from SUZERAINTY OF THE TYPE itself (any bonus pick) and the rate is diluted 3->4 to
                   # pay for the freedom. The Gen-2 Diplomacy deep node deepens back to per-3 (Div=12 top-up),
                   # so the all-in ceiling equals the old shipped rate exactly.
                   # NB the unlock is BOOLEAN (drafting the type's Shareable bonus flips it on; a 2nd CS of that
                   # type doesn't stack - no per-pop-per-count effect exists), so magnitude lives in this divisor.
                   # Push to 2 for "doubles your per-pop in that domain"; raise back toward 5 if late-game too hot.
$suzDiploAmt  = 2  # +Influence (YIELD_DIPLOMACY) per TOTAL suzerain, player-level (gated on the Diplomatic Shareable bonus)
$suzPopAmt    = 1  # free capital Population per Expansionist CS (signature; gated on the Expansionist Shareable bonus)
$suzPrimer    = 3  # flat Influence/turn (per Palace) to bootstrap winning the first city-states (ungated)
                      # (proven EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD, NOT per-pop - influence is player-level),
                      # gated behind that building's unlock node. The influence FLOOR the suzerain layer compounds.
                      # Raise for more influence; the Deity playtest showed influence (+5 total) was the binding cap.
$fortHealth = 25      # town-spec "Fort Town" bucket: +HP to all the player's Districts (toughens the tall city
$fortHeal   = 5       # against a numerically superior attacker) + heal/turn to the player's Units. Base Fort values.
$fortGold   = 1       # +Gold on Fortified districts (the Fort Town gold-on-fortifications benefit).
$religiousHappy = 2   # "Religious Site" Temple bucket: +Happiness on every Building (base value).
$resortAppeal   = 1   # "Resort" bucket: +Gold & +Happiness on Appealing tiles.
$resortNWPercent= 50  # "Resort" bucket: +% all yields on Natural-Wonder tiles (self-targets - only pays near a NW).
# ARCADIA DISCOVERY GATE (LOCKED 2026-07-13, Chris = 30%): Arcadia awakens once the player has discovered
# >= this PERCENT of the map's Natural Wonders (REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS +
# PercentageThreshold). 30% ~= 1 NW on Tiny / 2 on most sizes / 3 on Huge (map NW counts 3/4/5/6/7). Replaces
# the old binary "discovered ANY NW" gate. The % requirement can't tell water from land NWs, so it counts all;
# the design's separate "any water NW" water branch is a deferred edge-case refinement (2-water-NW map gap).
$arcadiaNWPercent = 30
$wonderAppealAmt = 2  # WONDER LANE B1: Appeal each of the player's wonders radiates to surrounding tiles. BINARY/flat
                      # (population doesn't decide it), via the B&B engine effect EFFECT_PLAYER_GRANT_WONDER_APPEAL.
                      # Feeds B2's Breathtaking rural ring + base appeal-happiness. =2 (2026-06-26, was 1): Charming
                      # is a 2-wide band (Appeal 3-4) and Breathtaking is 5+, so +1 only flipped tiles already at 4; +2
                      # lifts the WHOLE Charming ring (3 AND 4) to Breathtaking around a wonder (playtest: edge tiles didn't
                      # flip at +1). Stacks per adjacent wonder. Static-world property so it's tall-gated only (no node/pop).
                      # BALANCE DIAL: drop back toward 1 if Arcadia triggers too broadly at a Deity playtest.
$gwCultureAmt   = 1   # ITEM 6 relic/Great-Work amplifier: +Culture per Great Work in the city. Relics/Codices/
                      # Artifacts/Art are all Great Works and the kit hoards GW slots (Palace + Temple + collection),
                      # so this directly rewards the surviving Culture/relic lane. EFFECT_CITY_ADJUST_YIELD_PER_GREAT_WORK.
$suzTradeRangeAmt = 5 # SUZERAIN-DEFERRED: +Trade Route range (land+sea) per ECONOMIC city-state you are Suzerain of
                      # (EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE_PER_SUZERAIN_OF; base uses 5). Self-scales: 0 without one.
$suzResCapAmt   = 1   # SUZERAIN-DEFERRED: +Resource capacity per TOTAL suzerain (EFFECT_CITY_ADJUST_RESOURCE_CAP_PER_SUZERAIN).

# TOWN-SPEC WAREHOUSE handles (base-game warehouse-yield-change ids, defined in each age's data). Farming/Fishing
# Town = +Food on rural food tiles; Mining Town = +Production on rural production tiles; Trade Outpost happiness
# warehouse = +Happiness from resources. We grant these to the metropolis via EFFECT_CITY_GRANT_WAREHOUSE_YIELD
# (COLLECTION_PLAYER_CITIES - 100+ base uses, proven). Powers up RURAL tiles - a DISTINCT mechanic from the flat
# under-settlement-cap Food/Production (which is a player yield, not a tile boost), so the two don't double-count.

# WONDER LANE "Arcadia embraces the waters" (ROADMAP item 2) config. Per-water-type worked-tile yields. Design
# rule (2026-06-27): water is DIVERSE - each type gets its OWN yield set + per-Age amount, BUFFED above the
# mountain-peak baseline (peaks = $age.Preserve = 1/2/3), because water is the headline ceiling-breaker on
# archipelago / sea-heavy maps. Amounts are FIRST-PASS - tune at Deity. The broad MARINE type is kept at the peak
# baseline per-tile (its 3-yield SET plus the many sea tiles it covers are the real buff) and is the #1 balance dial;
# scarce premium types (reef, water Natural Wonder) carry higher amounts. Engine names VERIFIED against installed
# 1.4.1 + DLC data (not guessed): REQUIREMENT_PLOT_IS_RIVER(Navigable/Minor), _IS_LAKE, _BIOME_TYPE_MATCHES(BIOME_
# MARINE = coast+ocean in one), _FEATURE_TYPE_MATCHES(FeatureClassType = FEATURE_CLASS_AQUATIC = all reefs/atolls),
# _IS_NATURAL_WONDER (water-NW scoped to marine biome, DLC-agnostic). Each type -> one M-WaterYield modifier per
# hemisphere. Reef/water-NW tiles deliberately STACK with MARINE (premium scarce tiles = a spike, like A+B2 on peaks
# in EX/MO); de-dupe later if too hot. Amt is keyed by Sfx (AQ/EX/MO).
$waterTypes = [ordered]@{
    NAVRIVER = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_IS_RIVER"><Argument name="Navigable">true</Argument></Requirement>');
                  Yields='YIELD_FOOD, YIELD_GOLD';                                                      Amt=@{AQ=2;EX=3;MO=4} }
    MINRIVER = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_IS_RIVER"><Argument name="Minor">true</Argument></Requirement>');
                  Yields='YIELD_FOOD';                                                                  Amt=@{AQ=1;EX=2;MO=3} }
    LAKE     = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_IS_LAKE"/>');
                  Yields='YIELD_FOOD, YIELD_HAPPINESS';                                                 Amt=@{AQ=2;EX=3;MO=4} }
    MARINE   = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_BIOME_TYPE_MATCHES"><Argument name="BiomeType">BIOME_MARINE</Argument></Requirement>');
                  Yields='YIELD_FOOD, YIELD_GOLD, YIELD_SCIENCE';                                       Amt=@{AQ=1;EX=2;MO=3} }
    REEF     = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_FEATURE_TYPE_MATCHES"><Argument name="FeatureClassType">FEATURE_CLASS_AQUATIC</Argument></Requirement>');
                  Yields='YIELD_SCIENCE, YIELD_CULTURE';                                                Amt=@{AQ=2;EX=3;MO=4} }
    WATERNW  = @{ Reqs=@('<Requirement type="REQUIREMENT_PLOT_IS_NATURAL_WONDER"/>','<Requirement type="REQUIREMENT_PLOT_BIOME_TYPE_MATCHES"><Argument name="BiomeType">BIOME_MARINE</Argument></Requirement>');
                  Yields='YIELD_CULTURE, YIELD_PRODUCTION, YIELD_HAPPINESS, YIELD_SCIENCE, YIELD_FOOD'; Amt=@{AQ=3;EX=5;MO=7} }
}
# WATER LANE Option 4 - Tonga-style COASTAL FLOOR amount (per Age, keyed by Sfx). A FLAT, once-per-city +Food and
# +Production just for the metropolis being coastal (>=1 owned coast tile). The safety net Option 2 can't give: a
# tile-starved one-island start that works almost no water tiles still gets a guaranteed floor. ALWAYS-ON (tall +
# hemisphere only, NO discovery gate; 2026-06-27) - a floor must pay before you've explored, like C/B1. Balance
# dial: it stacks on everything and a coast tile is common on normal maps, so keep it modest; lower if too generous.
$waterFloorAmt = @{ AQ=2; EX=3; MO=4 }

# RAZING LANE (issue #3). Player-wide, tall-gated. "Destroy what you can't hold" made viable for a one-city empire.
# DESIGN (locked 2026-07-02 after in-game testing): every effect the player experiences is VISIBLE. Taking a city
# by force pays an on-screen LUMP (Gold + Influence); sacking its buildings pays per-building pillage; razing is near-
# instant. The old invisible ongoing bits were CUT: the -Influence offset (Item 1 - real but unseeable, and the base
# capture dialog still hardcodes the "-N Influence" warning so the UX actively contradicted it), the tiny Sci/Cul
# per-razed floor (Item 4), the ignore-capture-unrest (Item 7), and the war-cap (Item 6 - never applied + a non-problem).
# The capture LUMP folds in Item 1's job VISIBLY: you see Influence jump when you take the city instead of an invisible
# offset. Shape = Xerxes' MOD_GOLD/CULTURE_ON_CAPTURE_SETTLEMENT (proven): EFFECT_CITY_GRANT_YIELD on
# COLLECTION_PLAYER_CITIES, permanent, gated REQUIREMENT_PLAYER_FIRST_TIME_SETTLEMENT_OCCUPATION (fires per capture).
# Burn-tolerant tall gate (SOLO+1) since at the capture moment the just-taken city is your transient +1 settlement.
# The yield-crater during the ~3-turn burn (SOLO bonus gate off while the burning city is your 2nd settlement) is
# ACCEPTED and minimized by the maxed raze rate; zero-dip (an at-war OR-gate mod-wide) is PARKED - see docs/RAZING-PLAN.md.
$razeCaptureGold     = 200 # one-time Gold LUMP per city captured by combat, ScaleByGameAge -> 200/400/600 (aligned to the 1.4.1 govt tiers)
$razeCaptureInf      = 50  # one-time Influence LUMP per city captured by combat, ScaleByGameAge -> 50/100/150 (visibly softens razing's -Influence bleed)
$razeRateBonus       = 999 # +raze rate (COLLECTION_PLAYER_CITIES). Deliberately past the point of diminishing returns to
                           #   pin razing to its practical floor (in-game: pop-8 city 7->3 turns; smaller = faster). Harmless
                           #   on non-razing cities. This keeps the over-allowance dip as short as the engine allows (~3 turns).
$razePillageFlat     = 10  # +flat plunder per building your units pillage, per type (Gold + Science) - CONFIRMED in-game
                           # (the +% all-plunder amp was REMOVED 2026-07-02 - never showed in the building-pillage preview; the flat per-building amp stands as the pillage reward)

# $perPopDiv survives only as a DISPLAY divisor now: the per-pop reward loops that consumed it moved to the
# Ascendancy tree (Gen-2), but the base-node panel note text still quotes "+1 per N Urban Pop", so the value
# is read by Build-NoteText. Keyed 'SOLO' for historical continuity (the old per-hemisphere band name); there
# is only one value. The safety nets below keep their own lenient, non-revoking anti-wide gate (see the header
# and GitHub #25) - deliberately separate from any reward scaling.
$perPopDiv = @{ SOLO=2 }   # per-population display divisor: "+1 yield per 2 Urban Pop" in the note text.
# IDEAS 1 & 2 (2026-06-23): align with the 1.4.1 STAGED-HAPPINESS model (per-Age thresholds Joyous 20/40/60,
# Ecstatic 40/80/120 for AQ/EX/MO). Mechanic confirmed in 1.4.1 data: REQUIREMENT_SETTLEMENT_HAPPINESS_STAGE_MATCHES
# (Args HappinessStage + IsGreaterThanOrEquals); inverse="true" on it = "below that stage".
# IDEA 1 - happiness-stage PAYOFF lane: a metropolis that runs happy earns EXTRA per-pop yield (the lanes tall holds).
$stageJoyousDiv   = 4   # at >= JOYOUS:   +1 of each stage-yield per 4 Urban Pop
# IDEA 2 - stage-aware SAFETY NET: the -50% specialist Food+Happiness upkeep applies ONLY while the city is
# BELOW this stage, so a thriving (already-happy) city can't stack the mod's relief abusively on top of base-
# government specialist relief (Plutocracy Golden Age -2, Elective Republic, ETHICS/SCHOLARS/CHARTERS/ENLIGHTENMENT).
# DECOUPLED 2026-06-23: cutoff = ECSTATIC (not Joyous). Idea 1's payoff triggers at JOYOUS, so if the relief
# also cut at Joyous a specialist-dense city's happiness would oscillate at that line (losing the relief drops
# happiness back below Joyous -> relief returns), pinning it at the boundary and starving the Idea-1 payoff it
# needs. Cutting at ECSTATIC lets the city sit at Joyous WITH the relief (collecting the payoff); the relief only
# drops at Ecstatic, where huge headroom prevents oscillation and still caps the abusive govt-stack case.
# Lower to _JOYOUS for a tighter anti-stack (accepts oscillation) or _HAPPY for rescue-only.
$upkeepReliefMaxStage = 'HAPPINESS_STAGE_ECSTATIC'

# VICTORY-WONDER RECYCLE (ROADMAP issue #1, 2026-06-28). MODERN-only "Foundations" BUILDINGs: a tall, packed
# metropolis with no open tile can build one of these over an obsolete earlier-age district (buildings CAN overbuild
# obsolete districts; wonders can't - that's the whole trick). On completion the building REPLACE-converts ITSELF
# into the path's victory Wonder on that tile (1-step self-convert proven in-game 2026-06-28). The Foundations
# building is defined in data/modern/recycle.xml; its convert Modifier (MA_MO_RECLAIM_<Loc>) lives in the MO
# modifiers.xml and is bound via <ConstructibleModifiers> (NOT the attach wrapper). Gating keeps it tile-relief, never
# a shortcut: (a) the building's UNLOCK node = the wonder's OWN unlock (so it only appears once you've earned the wonder
# normally), (b) tall ($tallCap), (c) "don't already own the wonder" (no double-create). Cost = the wonder's own cost
# (no discount; you also sacrifice a building -> only ever worth it when you have no open tile).
$recycle = @(
    @{ Loc='WORLDS_FAIR'; Building='BUILDING_MA_WORLDS_FAIR_SITE'; Wonder='WONDER_WORLDS_FAIR';      Node='NODE_CIVIC_MO_MAIN_HEGEMONY'; Depth=2; Cost=2100; Icon='blp:wondericon_worldsfair' }       # Culture: World's Fair, gated on Cultural Hegemony MASTERY (depth 2); reuses the wonder's icon
    @{ Loc='MANHATTAN';   Building='BUILDING_MA_MANHATTAN_SITE';   Wonder='WONDER_MANHATTAN_PROJECT'; Node='NODE_TECH_MO_NUCLEAR_FISSION'; Depth=1; Cost=1800; Icon='blp:wondericon_manhattanproject' }   # Military: Manhattan Project, gated on Nuclear Fission (depth 1); reuses the wonder's icon
)

# ================= TALL RESOURCE REACH - the SURVEYOR (ROADMAP issue #12, 2026-07-02) =================
# A tall metropolis has a small footprint, so resources just out of reach stay out of reach. The Surveyor is a
# dedicated civilian granted to the metropolis at population milestones (and also buildable) that carries the base
# game's Prospector CLAIM_RESOURCE command: walk it to a resource tile within 5 hexes of a settlement and claim it
# into your borders (native 5-hex reach, resources only - the empty bridge tiles stay unworkable at range 3, proven).
# A claimed resource keeps its NORMAL base yields only - the per-resource amplifier that once paid extra was dropped
# pre-release (Arcadia already enriches worked tiles; no double-dip). The claim ability chain (ability type,
# UNIT_CLASS_PROSPECTOR tag, UnitAbilities/UnitClass_Abilities/ChargedUnitAbilities + the charge-grant modifier) is
# MODERN-only in the base game, so it is replicated into Antiquity + Exploration here; Modern needs only the unit
# tagged UNIT_CLASS_PROSPECTOR (proven). Full research: docs/SURVEYOR-RESOURCE-REACH-PLAN.md.
$surveyorGrantAges  = @()                      # NO FREE GRANT - the Surveyor is BUILDABLE-ONLY in every Age (2026-07-02). Reason:
                                               #   the Surveyor self-consumes on claim (same command as the base Prospector, confirmed
                                               #   in-game), so a milestone grant gated on "own fewer than 1" would re-grant a fresh free one
                                               #   each time one is spent (unlimited), and a reliable "exactly once at pop 5" isn't achievable
                                               #   (run-once doesn't fire deferred through the attach wrapper). Buildable-only sidesteps all of
                                               #   that. To re-enable a grant, put an Age back here (e.g. @('AQ')) - M-GrantSurveyor still exists.
$surveyorMoves    = 3                          # civilian movement (matches the base Prospector)
$surveyorCost     = @{ AQ=30; EX=50; MO=70 }   # PRODUCTION cost when built (buildable is a 2nd source; also tall-gated)
$surveyorCharges  = 1                          # CLAIMS PER SURVEYOR (2026-07-02, in-game: base Prospector ships 1 charge and self-
                                               #   consumes on claim; keep that one-shot model). Each Surveyor claims $surveyorCharges resource,
                                               #   then vanishes (same UNITCOMMAND_CLAIM_RESOURCE self-consume as the Prospector). Build another to expand.
$surveyorRecharge = 999                        # charge recharge turns = 999 => NO regen (moot at 1 charge: the unit self-consumes before it could
                                               #   recharge). One-shot by design; build more Surveyors to reach further.
$surveyorOverrideModernRecharge = $false       # Modern's CHARGED_ABILITY_CLAIM_RESOURCE is SHARED with base America's Prospector, so leaving it
                                               #   alone ($false) avoids changing America. Trade-off: a BUILT Modern Surveyor keeps the base 1-charge/
                                               #   5-turn-recharge (reusable) rather than the AQ/EX 2-charges-capped. Set $true to force Modern to
                                               #   $surveyorRecharge too (also changes AI America's Prospector). (Charge COUNT in MO stays base=1.)
$surveyorUnit     = 'UNIT_MA_SURVEYOR'

# NB (2026-07-24, issue #22): a reader here used to scan the installed base game's Resource_YieldChanges
# on every build to feed a per-resource amplifier (M-ResourceReach). The amplifier was dropped pre-release
# - a claimed resource keeps its base yields only - so both the reader and the emitter were deleted, along
# with the build-time dependency on the game install. The design and the exact effect it used are written
# up in docs/SURVEYOR-RESOURCE-REACH-PLAN.md if the dial is ever wanted.

# Portable mod-root resolution (no hardcoded user paths). Works in BOTH layouts:
#   - dev monorepo:   <repo>\tools\gen-ascendant.ps1  with the mod at <repo>\mods\<name>\
#   - standalone repo: <repo>\tools\gen-ascendant.ps1  with the mod AT the repo root (<repo>\<name>.modinfo)
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path $MyInvocation.MyCommand.Path -Parent }
$repoRoot  = Split-Path $scriptDir -Parent
$modName   = if ($TestMode) { 'metropolis-ascendant-test' } else { 'metropolis-ascendant' }
$devModDir = Join-Path $repoRoot "mods\$modName"
$modDir    = if (Test-Path (Join-Path $devModDir "$modName.modinfo")) { $devModDir }
             elseif (Test-Path (Join-Path $repoRoot "$modName.modinfo")) { $repoRoot }
             else { $devModDir }   # default to dev layout (first run before files exist)
$root = Join-Path $modDir 'data'
$NL = "`r`n"

function HemiArg($hemi) {
    switch ($hemi) {
        'HL' { '<Argument name="OnlyHomelands">true</Argument>' }
        'DL' { '<Argument name="OnlyDistantlands">true</Argument>' }
        default { '' }
    }
}
function HemiCityReq($hemi) {
    switch ($hemi) {
        'HL' { "`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_DISTANT_LANDS`" inverse=`"true`"/>$NL" }
        'DL' { "`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_DISTANT_LANDS`"/>$NL" }
        default { '' }
    }
}
function Owner($node) {
    if ($TestMode) { return '' }   # test build drops the tech-node gate so bonuses are live from turn 1
    "`t`t<OwnerRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE`"><Argument name=`"ProgressionTreeNodeType`">$node</Argument><Argument name=`"MinDepth`">1</Argument></Requirement>$NL`t`t</OwnerRequirements>$NL"
}
function PopReq($pop) {
    "`t`t`t<Requirement type=`"REQUIREMENT_CITY_POPULATION`"><Argument name=`"MinUrbanPopulation`">$pop</Argument></Requirement>$NL"
}
# 1.4.1 happiness-stage gate (Ideas 1 & 2). inverse=$true means "city is BELOW $stage". Subject (per-city)
# requirement; mirrors the base-game government pattern (e.g. MOD_CLASSICAL_REPUBLIC_PASSIVE_JOYOUS_CITIES).
function StageReq($stage, $inverse) {
    $i = if ($inverse) { ' inverse="true"' } else { '' }
    "`t`t`t<Requirement type=`"REQUIREMENT_SETTLEMENT_HAPPINESS_STAGE_MATCHES`"$i><Argument name=`"IsGreaterThanOrEquals`">true</Argument><Argument name=`"HappinessStage`">$stage</Argument></Requirement>$NL"
}
# one REQUIREMENT_PLAYER_HAS_X_SETTLEMENTS block
function Settle($n, $inv, $onlyCities, $hemiArg) {
    $i = if ($inv) { ' inverse="true"' } else { '' }
    "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_X_SETTLEMENTS`"$i>$NL`t`t`t`t<Argument name=`"OnlyCities`">$onlyCities</Argument><Argument name=`"OnlyTowns`">false</Argument>$hemiArg$NL`t`t`t`t<Argument name=`"RequiredCount`">$n</Argument>$NL`t`t`t`t<Argument name=`"CountPerOwnSettlement`">1</Argument><Argument name=`"CountPerConqueredSettlement`">1</Argument>$NL`t`t`t</Requirement>"
}
# ---- GEN-2 PILLAR GATE (2026-07-19) ----------------------------------------------------------
# The tall-engine pillars (Arcadia rural ring / peaks / waters, wonder-happiness, mountain+water
# adjacency, coastal floor) now gate on TOTAL settlements vs the EARNED allowance - the exact
# same windows as the Ascendancy tree. The old per-hemisphere SOLO band was v1's retired
# one-per-hemisphere rule and wrongly killed the pillars in legal 2-3 settlement empires
# (found in-game 2026-07-19: a 3/3 empire's capital mountains paid nothing). Hemisphere twins
# are RETIRED for this family: one modifier, pays everywhere (total-footprint law - towns
# count, placement free).
# ⚠ REBUILT 2026-07-21 (2nd iteration, after the in-game proof that a Triumph condition is
# evaluated ONCE at bind/attach and never re-evaluated - neither in-leaf on attached modifiers NOR
# on always-bound wrappers; attachments persist in saves). Delivery now rides only PROVEN paths:
#   W1 (floor)  -> the always ATTACH_ALL wrapper; count reqs in-leaf re-evaluate (proven).
#   AQ/EX W2    -> the age's EXPANSION FEAT REWARD attach (fires at Triumph completion - proven;
#                  handed to gen-ascendancy via tools/pillar-window-ids.json, since that script
#                  owns the feat reward wiring and runs second in the publish pipeline).
#   MO W2 (=3)  -> ATTACH_ALL, count-only: any legitimate 3 has a charter; only the punished
#                  over-allowance state leaks.  MO W3 (=4) -> the MO feat reward (manifest).
function PillarWindows($sfx) {
    switch ($sfx) {
        'AQ' { @( @{ W='_W1'; R=@((Settle 2 $true 'false' '')); Route='ALL' },
                  @{ W='_W2'; R=@((Settle 2 $false 'false' ''), (Settle 3 $true 'false' '')); Route='REWARD' } ) }
        'EX' { @( @{ W='_W1'; R=@((Settle 3 $true 'false' '')); Route='ALL' },
                  @{ W='_W2'; R=@((Settle 3 $false 'false' ''), (Settle 4 $true 'false' '')); Route='REWARD' } ) }
        'MO' { @( @{ W='_W1'; R=@((Settle 3 $true 'false' '')); Route='ALL' },
                  @{ W='_W2'; R=@((Settle 3 $false 'false' ''), (Settle 4 $true 'false' '')); Route='ALL' },
                  @{ W='_W3'; R=@((Settle 4 $false 'false' ''), (Settle 5 $true 'false' '')); Route='REWARD' } ) }
    }
}
# Victory-wonder recycle (issue #1): the run-once REPLACE that turns a Foundations BUILDING into its victory Wonder.
# COLLECTION_OWNER, bound to the building via <ConstructibleModifiers> (recycle.xml) so it fires on completion - NOT
# in the attach wrapper. Gated tall ($tallCap) + "don't already own the wonder" (inverse REQUIREMENT_PLAYER_HAS_CONSTRUCTIBLE,
# so it can never double-create). The building's UNLOCK node gate (recycle.xml) is what makes it tile-relief, not a shortcut.
function M-Reclaim($r) {
    $reqs  = "`t`t<SubjectRequirements>$NL"
    $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_CONSTRUCTIBLE`" inverse=`"true`"><Argument name=`"ConstructibleType`">$($r.Wonder)</Argument></Requirement>$NL"
    $reqs += (Settle $tallCap $true 'false' '') + $NL
    $reqs += "`t`t</SubjectRequirements>$NL"
    "`t<Modifier id=`"MA_MO_RECLAIM_$($r.Loc)`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_REPLACE_CONSTRUCTIBLE`" permanent=`"true`" run-once=`"true`">$NL$reqs`t`t<Argument name=`"Destroy`">$($r.Building)</Argument>$NL`t`t<Argument name=`"Create`">$($r.Wonder)</Argument>$NL`t</Modifier>"
}

function M-Upkeep($sfx,$pop,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    "`t<Modifier id=`"MA_${sfx}_T1_SPECIALIST_UPKEEP${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_WORKER_MAINTENANCE_EFFICIENCY`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(StageReq $upkeepReliefMaxStage $true)$(Settle 5 $true 'true' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_FOOD, YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Percent`">50</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_SAFETY_DESCRIPTION</Argument>$NL`t</Modifier>"
}
function M-Happiness($sfx,$pop,$amt,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    "`t<Modifier id=`"MA_${sfx}_T1_HAPPINESS${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(Settle 5 $true 'true' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_TIER1_DESCRIPTION</Argument>$NL`t</Modifier>"
}
# WONDER LANE "C" - Happiness adjacency around Wonders (Classical Revival recipe). The custom rule
# MA_WonderHappiness (defined in data/shared/constructibles.xml; RequiresActivation) = a BUILDING next to a Wonder
# district gets +1 Happiness. This modifier just ACTIVATES it (EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY).
# BINARY + STRUCTURAL, gated ONLY on the tall model (SOLO + hemisphere) - deliberately NO tech-node gate and NO
# population tier (2026-06-26):
#   - Wonder-adjacency is a STATIC-WORLD property; a per-Age node gate would make it blink OFF at every Age
#     transition until re-research even though the wonder/world didn't change.
#   - It's binary - population size doesn't decide whether a wonder confers Happiness - so no pop tiers / no scaling.
#   - It self-scopes: no wonder (or no adjacent building) = nothing, so it needs no gate beyond "are you the tall city."
# (To change the magnitude, edit MA_WonderHappiness's YieldChange in data/shared/constructibles.xml - not here.)
# Delivered through the COLLECTION_MAJOR_PLAYERS attach wrapper. VERIFY in-game: (a) activation resolves through the
# player attach wrapper, (b) DISTRICT_WONDER counts player-built wonders for the adjacent building.
function M-WonderHappyAdj($sfx,$win) {
    $gate = ($win.R) -join $NL
    "`t<Modifier id=`"MA_${sfx}_WONDER_HAPPY_ADJ$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"ConstructibleAdjacency`">MA_WonderHappiness</Argument>$NL`t</Modifier>"
}
# WONDER LANE "B2" - Appeal->yield "Preserve" ring. Mirrors the Heian Hoo-Do / TRAIT_MOD_APPEALING_CULTURE template
# (DLC\heian\modules\data\civilizations-shared-gameeffects.xml): COLLECTION_PLAYER_PLOT_YIELDS + EFFECT_PLOT_ADJUST_YIELD
# + REQUIREMENT_PLOT_HAS_APPEAL(UseAppealDoubleHappinessThreshold=BREATHTAKING) + REQUIREMENT_PLOT_DISTRICT_CLASS(RURAL).
# Grants the AGE's amount of Cul/Prod/Happy/Sci/Food on every RURAL plot at Breathtaking appeal. Uses the PLAYER-rooted
# plot collection so it delivers through the COLLECTION_MAJOR_PLAYERS attach wrapper (the city-context
# COLLECTION_CITY_PLOT_YIELDS silently no-ops attached to a player). It's YIELDS, so node-gated (Wonders node) and
# scales BY AGE (AQ 1 / EX 2 / MO 3; $age.Preserve) - yields grow per era while appeal mechanics stay pop-free (2026-06-26;
# static-world rule). Tall-gated: SOLO (hemisphere-scoped settlement count) in OwnerRequirements like M-CombatStrength; the
# plot is scoped to its hemisphere via REQUIREMENT_PLOT_IS_HOMELANDS (inverse=distant) so player-wide delivery doesn't
# bleed the homeland ring onto distant tiles. (Tooltip LOC deferred to a text pass, like C.)
function M-AppealYield($sfx,$amt,$win,$excludeMtn) {
    $reqs = @()
    # DISCOVERY GATE (2026-06-26): Arcadia awakens once you've discovered a Natural Wonder - an EXPLORATION
    # unlock, not a tree unlock. It's a YIELD so discovery-gating is fine even if it re-evaluates at an Age
    # boundary. C/B1 stay always-on (no discovery gate) so they never blink + survive EX/MO advanced starts.
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>" }
    $reqs += $win.R
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    # DE-DUPE (2026-06-26): when $excludeMtn (AQ only), the rural ring SKIPS mountain tiles so a terraced peak gets
    # ONLY the mountain yield (A), not A+B2. In EX/MO $excludeMtn is false, so a Breathtaking terraced mountain stacks BOTH
    # A+B2 - a deliberate LATE-GAME power spike (like Civ 6 Preserves) to help 2 cities close the Deity yield gap.
    $noMtn = if ($excludeMtn) { "`t`t`t<Requirement inverse=`"true`" type=`"REQUIREMENT_PLOT_TERRAIN_TYPE_MATCHES`"><Argument name=`"TerrainType`">TERRAIN_MOUNTAIN</Argument></Requirement>$NL" } else { '' }
    "`t<Modifier id=`"MA_${sfx}_APPEAL_YIELD$($win.W)`" collection=`"COLLECTION_PLAYER_PLOT_YIELDS`" effect=`"EFFECT_PLOT_ADJUST_YIELD`">$NL$owner`t`t<SubjectRequirements>$NL$noMtn`t`t`t<Requirement type=`"REQUIREMENT_PLOT_DISTRICT_CLASS`"><Argument name=`"DistrictClass`">RURAL</Argument></Requirement>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLOT_HAS_APPEAL`"><Argument name=`"UseAppealDoubleHappinessThreshold`">true</Argument></Requirement>$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_CULTURE, YIELD_PRODUCTION, YIELD_HAPPINESS, YIELD_SCIENCE, YIELD_FOOD</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_ARCADIA_LABEL</Argument>$NL`t</Modifier>"
}
# WONDER LANE "B1" - wonders grant Appeal. EFFECT_PLAYER_GRANT_WONDER_APPEAL (arg Amount) on COLLECTION_OWNER: every
# wonder the player owns radiates Amount Appeal to surrounding tiles ("expand Hoo-Do to all wonders" - native + player-
# scoped). BINARY/flat (no pop), and NO tech-node gate - appeal-granting is a static-world property that must not blink
# off at Age transitions (memory: civ7-age-transition-static-functions). Tall-gated on total settlement count (Settle
# $tallCap, lenient player-level gate like the trade-route/range bonuses, so a 1-homeland+1-distant tall player keeps
# it). Self-scopes: no wonder = nothing granted. Player-wide -> emit ONCE per age (guard to the non-DL pass).
# NB EFFECT_PLAYER_GRANT_WONDER_APPEAL's only on-disk definition is in the Heian (Brush & Blade) DLC module, but it's an
# ENGINE effect shipped with the 1.4.1 update -> should resolve without the DLC active. VERIFY (disable B&B, load): if it
# errors/no-ops without the DLC, gate this behind a DLC-present check (the mod currently declares "No DLC required").
function M-WonderAppeal($sfx,$amt) {
    "`t<Modifier id=`"MA_${sfx}_WONDER_APPEAL`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_GRANT_WONDER_APPEAL`">$NL`t`t<SubjectRequirements>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# WONDER LANE "M3" = ARCADIA, THE PEAKS. Once Arcadia is awake the metropolis draws bounty from adjacent MOUNTAINS too
# (the apex of natural beauty). TWO parts:
#  (1) M-MountainUnlock - grant the base-game IMPROVEMENT_INCA_MOUNTAIN "faux improvement" (EFFECT_PLAYER_GRANT_CONSTRUCTIBLE_UNLOCK,
#      COLLECTION_OWNER) so the tall player can WORK mountain tiles. Nepal proves this works in ALL Ages (it reuses the same
#      base improvement from Antiquity; its own comment: "The Incans are base game, so just reusing the same faux improvement").
#  (2) M-MountainYield - yields on worked mountain tiles. Mirrors the Inca "Apus" yield (EFFECT_PLOT_ADJUST_YIELD on
#      COLLECTION_PLAYER_PLOT_YIELDS, TerrainType=TERRAIN_MOUNTAIN + not-urban) = the SAME effect/collection as the rural ring
#      (M-AppealYield), so it shares the DISCOVERY gate + tall + hemisphere scoping. Yields = Prod/Sci/Cul (peaks = industry/
#      FULL ARCADIA 5-set (Cul/Prod/Happy/Sci/Food - treated as Breathtaking; 2026-06-26), scaled by Age ($age.Preserve).
# BALANCE: mountain yield applies to EVERY worked mountain (no Breathtaking gate, unlike the rural ring), so it's potent on
# mountainous maps -> prime tuning dial (trim the yield set or the amount after a Deity playtest).
# COMPANION: M-MountainAdj (Model B) layers the Machu-Picchu wildcard on top - every Building/Wonder adjacent to a Mountain
# gains +Cul/+Gold per mountain (scaled 1/2/3 by Age), via the MA_MtnCul#/MA_MtnGold# wildcard rules in data/shared/constructibles.xml.
function M-MountainUnlock($sfx) {
    $reqs = @()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>" }
    $reqs += (Settle $tallCap $true 'false' '')
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    "`t<Modifier id=`"MA_${sfx}_MOUNTAIN_UNLOCK`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_GRANT_CONSTRUCTIBLE_UNLOCK`">$NL$owner`t`t<Argument name=`"ConstructibleType`">IMPROVEMENT_INCA_MOUNTAIN</Argument>$NL`t</Modifier>"
}
function M-MountainYield($sfx,$amt,$win) {
    $reqs = @()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>" }
    $reqs += $win.R
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    "`t<Modifier id=`"MA_${sfx}_MOUNTAIN_YIELD$($win.W)`" collection=`"COLLECTION_PLAYER_PLOT_YIELDS`" effect=`"EFFECT_PLOT_ADJUST_YIELD`">$NL$owner`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLOT_TERRAIN_TYPE_MATCHES`"><Argument name=`"TerrainType`">TERRAIN_MOUNTAIN</Argument></Requirement>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLOT_DISTRICT_CLASS`" inverse=`"true`"><Argument name=`"DistrictClass`">CITYCENTER, URBAN, WONDER</Argument></Requirement>$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_CULTURE, YIELD_PRODUCTION, YIELD_HAPPINESS, YIELD_SCIENCE, YIELD_FOOD</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_ARCADIA_PEAKS_LABEL</Argument>$NL`t</Modifier>"
}
# MOUNTAIN LANE "B" = Machu-Picchu WILDCARD. Activate MA_MtnCul#/MA_MtnGold# (data/shared/constructibles.xml) so every
# BUILDING and WONDER adjacent to a Mountain gains +# Culture / +# Gold per mountain (# = $age.Preserve, i.e. +1/+2/+3 by
# Age - each Age activates only its own numbered rule, no stacking). Same EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY
# recipe as C + the base Machu Picchu (wildcard = no ConstructibleClass = all constructibles incl wonders).
# COLLECTION_PLAYER_CITIES, gated on Arcadia discovery (OwnerRequirements) + tall SOLO + hemisphere (SubjectRequirements).
# Emits one Culture + one Gold activation modifier per hemisphere. TestMode drops the discovery gate (live from turn 1).
function M-MountainAdj($sfx,$num,$win) {
    $gate = ($win.R) -join $NL
    $disc = if ($TestMode) { '' } else { "`t`t<OwnerRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>$NL`t`t</OwnerRequirements>$NL" }
    $reqs = "`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$gate$NL`t`t</SubjectRequirements>$NL"
    $cul = "`t<Modifier id=`"MA_${sfx}_MTN_ADJ_CUL$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY`">$NL$disc$reqs`t`t<Argument name=`"ConstructibleAdjacency`">MA_MtnCul${num}</Argument>$NL`t</Modifier>"
    $gld = "`t<Modifier id=`"MA_${sfx}_MTN_ADJ_GOLD$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY`">$NL$disc$reqs`t`t<Argument name=`"ConstructibleAdjacency`">MA_MtnGold${num}</Argument>$NL`t</Modifier>"
    "$cul$NL$gld"
}
# WONDER LANE "Arcadia embraces the waters" (ROADMAP item 2). The ceiling-breaker M3 gave the peaks, but for WATER:
# on archipelago / sea-heavy maps a one-island metropolis is tile-starved, so once Arcadia awakens it draws bounty
# from the surrounding water too. THREE parts, all gated like the peaks (Arcadia discovery + tall + hemisphere):
#  (Option 2) M-WaterYield - per-water-type worked-tile yields. ONE EFFECT_PLOT_ADJUST_YIELD modifier per water type
#      ($waterTypes), each with its OWN yield set + per-Age amount. Same effect/collection/gating as M-MountainYield -
#      just swaps TERRAIN_MOUNTAIN for the per-type plot requirement. NB MARINE matches BOTH coast and ocean; in AQ
#      ocean can't be worked so those plots are inert (coast still pays), EX needs the Option-3 grant, MO works ocean
#      natively. not-urban (CITYCENTER/URBAN/WONDER inverse) so a water tile under a district doesn't double-pay.
#  (Option 3) M-WaterUnlock - grant IMPROVEMENT_HAWAII_FISHING_BOAT (base game, RURAL on TERRAIN_OCEAN, no resource
#      gate) so the tall player can WORK empty ocean. The literal sea-twin of M-MountainUnlock's INCA_MOUNTAIN grant
#      (same effect/collection, sits 3 lines away in the Hawaii trait). EX-ONLY (AQ can't work ocean; MO works natively).
#  (Option 1) M-WaterAdj - adjacency companion (Machu-Picchu wildcard model): every Building/Wonder adjacent to Coast
#      gains +Gold and adjacent to a Navigable River gains +Production, per adjacent tile, +1/+2/+3 by Age via the
#      MA_CoastGold#/MA_RiverProd# wildcard rules in data/shared/constructibles.xml.
function M-WaterYield($sfx,$type,$wt,$win) {
    $reqs = @()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>" }
    $reqs += $win.R
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    $plotReqs = (($wt.Reqs | ForEach-Object { "`t`t`t$_" }) -join $NL) + $NL
    $amt = $wt.Amt[$sfx]
    "`t<Modifier id=`"MA_${sfx}_WATER_${type}_YIELD$($win.W)`" collection=`"COLLECTION_PLAYER_PLOT_YIELDS`" effect=`"EFFECT_PLOT_ADJUST_YIELD`">$NL$owner`t`t<SubjectRequirements>$NL$plotReqs`t`t`t<Requirement type=`"REQUIREMENT_PLOT_DISTRICT_CLASS`" inverse=`"true`"><Argument name=`"DistrictClass`">CITYCENTER, URBAN, WONDER</Argument></Requirement>$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$($wt.Yields)</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_ARCADIA_WATERS_LABEL</Argument>$NL`t</Modifier>"
}
function M-WaterUnlock($sfx) {
    $reqs = @()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>" }
    $reqs += (Settle $tallCap $true 'false' '')
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    "`t<Modifier id=`"MA_${sfx}_WATER_UNLOCK`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_GRANT_CONSTRUCTIBLE_UNLOCK`">$NL$owner`t`t<Argument name=`"ConstructibleType`">IMPROVEMENT_HAWAII_FISHING_BOAT</Argument>$NL`t</Modifier>"
}
function M-WaterAdj($sfx,$num,$win) {
    $gate = ($win.R) -join $NL
    $disc = if ($TestMode) { '' } else { "`t`t<OwnerRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_DISCOVERED_X_NATURAL_WONDERS`"><Argument name=`"PercentageThreshold`">$arcadiaNWPercent</Argument></Requirement>$NL`t`t</OwnerRequirements>$NL" }
    $reqs = "`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$gate$NL`t`t</SubjectRequirements>$NL"
    $gld = "`t<Modifier id=`"MA_${sfx}_WATER_ADJ_GOLD$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY`">$NL$disc$reqs`t`t<Argument name=`"ConstructibleAdjacency`">MA_CoastGold${num}</Argument>$NL`t</Modifier>"
    $prd = "`t<Modifier id=`"MA_${sfx}_WATER_ADJ_PROD$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ACTIVATE_CONSTRUCTIBLE_ADJACENCY`">$NL$disc$reqs`t`t<Argument name=`"ConstructibleAdjacency`">MA_RiverProd${num}</Argument>$NL`t</Modifier>"
    "$gld$NL$prd"
}
# WATER LANE Option 4 - Tonga-style COASTAL FLOOR. A flat, once-per-city +Food/+Production just for the metropolis
# being coastal (REQUIREMENT_CITY_HAS_TERRAIN TERRAIN_COAST Amount=1 = the city owns >=1 coast tile). Tonga's signature
# (DLC\tonga) is EFFECT_CITY_ADJUST_CONSTRUCTIBLE_YIELD on a beachfront Palace/City Hall; we use the cleaner city-coastal
# gate (doesn't require the Palace itself on the beach, and AND-combines with the tall gate) + flat EFFECT_CITY_ADJUST_
# YIELD, matching the rest of the kit (per-Age amount). ALWAYS-ON: tall + hemisphere only, NO discovery gate - a floor
# must pay before you've explored, like the structural pieces C/B1. Two modifiers (base EFFECT_CITY_ADJUST_YIELD takes a
# single YieldType - Food + Production split, mirroring base MOD_FOUNDER_BELIEF_DOMESTIC_FOOD/_PRODUCTION).
function M-WaterFloor($sfx,$amt,$win) {
    $gate = ($win.R) -join $NL
    $reqs = "`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_HAS_TERRAIN`"><Argument name=`"TerrainType`">TERRAIN_COAST</Argument><Argument name=`"Amount`">1</Argument></Requirement>$NL$gate$NL`t`t</SubjectRequirements>$NL"
    $food = "`t<Modifier id=`"MA_${sfx}_WATER_FLOOR_FOOD$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD`">$NL$reqs`t`t<Argument name=`"YieldType`">YIELD_FOOD</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_ARCADIA_WATERS_LABEL</Argument>$NL`t</Modifier>"
    $prod = "`t<Modifier id=`"MA_${sfx}_WATER_FLOOR_PROD$($win.W)`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD`">$NL$reqs`t`t<Argument name=`"YieldType`">YIELD_PRODUCTION</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_ARCADIA_WATERS_LABEL</Argument>$NL`t</Modifier>"
    "$food$NL$prod"
}
# ============================ SUZERAIN LAYER (Phase 3, 2026-06-20) ============================
# The tall player's substitute for going WIDE: bonuses that AUTO-SCALE with how many city-states you lead
# (no city count needed). All effects grounded in base-game age-(exploration|modern)/data/independents-
# gameeffects.xml + religion-gameeffects.xml. The two domains the mod had NO home for live ONLY here:
# Expansionist->Food and Diplomatic->Influence (weighted higher). EVERYTHING carries the <4-settlement
# anti-wide gate: a WIDE AI can suzerain many CS too, so without it we'd hand them the bonus. Delivered via
# the COLLECTION_MAJOR_PLAYERS attach wrapper like the rest of the kit.
# NB: in-game "Influence" = YIELD_DIPLOMACY internally (the pantheon altar proves it).
#
# DESIGN (2026-06-20; DECOUPLED 2026-07-13): flat per-CS yields are USELESS for a one-city tall player (CS
# count is tiny; improvements are 1-per-city by meta). The ONLY axis that scales for tall is POPULATION. So we
# grant a PER-POP yield keyed to the CITY-STATE TYPE you are Suzerain of. Suzerainty is the UNLOCK, your pop is
# the MULTIPLIER. GATE = REQUIREMENT_PLAYER_HAS_X_TRIBUTARIES_OF_TYPE (base-verified) - i.e. simply HOLDING the
# suzerainty, regardless of which bonus you draft. NOTHING is attached to the draft menu: no reward rides the
# Shareable-bonus pick and no menu DESCRIPTION text is overridden (both were the pre-decouple "Route A" design,
# now fully removed). The explanation lives on the civic SUZERAIN note + the dashboard's Protectorates panel.
#
# (1) Five CITY yields, PER-POP, from SUZERAINTY OF THE TYPE itself (GEN-2 DECOUPLE 2026-07-13:
#     the old REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS gate forced the Shareable pick every time and
#     fought the Gen-2 improvement-picking feats; now any bonus pick qualifies - the tributary
#     requirement is base-verified, Conqueror-set usage). $shareBonus param retained for caller
#     compatibility, no longer read.
function M-SuzerainPerPop($sfx,$shareBonus,$yield,$csType,$div) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_${csType}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_POPULATION`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_X_TRIBUTARIES_OF_TYPE`"><Argument name=`"Amount`">1</Argument><Argument name=`"CityStateType`">$csType</Argument></Requirement>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Urban`">true</Argument><Argument name=`"Rural`">false</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_SUZERAIN_LABEL</Argument>$NL`t</Modifier>"
}
# (2) DIPLOMATIC->Influence. Influence is PLAYER-level (can't ride the per-pop city effect), so EFFECT_PLAYER_
#     ADJUST_YIELD_PER_SUZERAIN (base: HOSPITALITY_MOD_SUZERAINS) grants +Amount YIELD_DIPLOMACY per TOTAL
#     suzerain (any type) - a compounding loop. GEN-2 DECOUPLE: gated on Suzerainty of a DIPLOMATIC
#     city-state (was the Diplomatic Shareable pick) + anti-wide.
function M-SuzerainDiplo($sfx,$shareBonus,$amt) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_DIPLOMATIC`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_YIELD_PER_SUZERAIN`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_X_TRIBUTARIES_OF_TYPE`"><Argument name=`"Amount`">1</Argument><Argument name=`"CityStateType`">DIPLOMATIC</Argument></Requirement>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_DIPLOMACY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_SUZERAIN_LABEL</Argument>$NL`t</Modifier>"
}
# (3) FREE-POP — REMOVED 2026-06-20. Was: each EXPANSIONIST CS adds free capital population via
#     EFFECT_ADJUST_PLAYER_FREE_POLPULATION_CAPITAL_ON_CITY_STATE. Playtest showed it never fires through our
#     gating: it's a one-shot grant at the become-suzerain event, but ELIGIBLE_CS_BONUS flips true only after,
#     so the window is missed. No continuous pop-per-CS effect exists. Builder deleted; per-pop Food covers Exp.
# (4) INFLUENCE PRIMER (bootstrap): the layer is a paper layer without influence to WIN the first city-states
#     (Deity playtest: tall had +5 influence, lost every envoy race). Influence is only ever emitted via
#     EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD (pantheon altar pattern), so we grant +Amount YIELD_DIPLOMACY
#     per BUILDING_PALACE (every capital has exactly 1 -> effectively flat + capital-only). UNGATED by node so
#     it's live early to bootstrap; anti-wide gated so the wide AI doesn't get it. Then (2) compounds it.
function M-Influence($sfx,$amt) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_PRIMER`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD`">$NL`t`t<SubjectRequirements>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_DIPLOMACY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"ConstructibleType`">BUILDING_PALACE</Argument>$NL`t</Modifier>"
}
# ============================= RAZING LANE (issue #3) =============================
# Player-wide, emitted once per FanOut age via the attach wrapper. Tall-gated so a wide conquer-and-keep empire
# gains none of it. See docs/RAZING-PLAN.md. Everything the player experiences is VISIBLE (see config header).
# TALL GATE: all three shipped effects run during the war/capture window (transiently +1 settlement), so all use
# the BURN-TOLERANT gate (Settle $tallCap+1) - a wide empire (3+ founded/kept) is still excluded.
# CAPTURE LUMP (folds in the old invisible Influence offset, VISIBLY): a one-time Gold + Influence burst per city
# taken by combat. Exact clone of Xerxes' MOD_GOLD/CULTURE_ON_CAPTURE_SETTLEMENT (EFFECT_CITY_GRANT_YIELD on
# COLLECTION_PLAYER_CITIES, permanent, gated REQUIREMENT_PLAYER_FIRST_TIME_SETTLEMENT_OCCUPATION -> fires per capture;
# + REQUIREMENT_CITY_TRANSFER_TYPE_MATCHES BY_COMBAT so only forceful captures pay). PER-AGE LITERALS (2026-07-04):
# was `type="ScaleByGameAge" extra="100"` with one base — but that engine formula is undocumented/unverified, so the
# actual EX/MO payouts were unknown even to us. Now baked to the ADVERTISED progression (base x1/x2/x3 by Age:
# Gold 200/400/600, Influence 50/100/150) so the numbers are deterministic and the dashboard/docs can state them.
function M-RazeCapture($sfx,$yield,$amt) {
    $ageMult = @{ AQ = 1; EX = 2; MO = 3 }[$sfx]; if (-not $ageMult) { $ageMult = 1 }
    $lit = $amt * $ageMult
    "`t<Modifier id=`"MA_${sfx}_RAZE_CAPTURE_$yield`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_GRANT_YIELD`" permanent=`"true`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_FIRST_TIME_SETTLEMENT_OCCUPATION`"/>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_TRANSFER_TYPE_MATCHES`"><Argument name=`"TransferType`">BY_COMBAT</Argument></Requirement>$NL$(Settle ($tallCap+1) $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_$yield</Argument>$NL`t`t<Argument name=`"Amount`">$lit</Argument>$NL`t</Modifier>"
}
# Item 2: burn faster. The base game's only use (Qajar SOLTAN_MOD_RAIZING) is a UNIT-ABILITY modifier bound via
# UnitAbilityModifiers -> ABILITY_SOLTAN (COLLECTION_UNIT_OCCUPIED_CITY, needs a garrisoned unit). Delivered via
# OUR player attach wrapper that collection never resolves to a unit, so it silently did nothing (in-game confirmed
# 2026-07-02: raze timer unchanged, unit on/off made no difference). FIX A: re-deliver as a plain city effect on
# COLLECTION_PLAYER_CITIES (a settlement being razed is still one of your cities) - wrapper-deliverable, no garrison.
# Burn-tolerant gate (SOLO+1) in SubjectRequirements since it runs during the 2-settlement burn window.
# [TEST-WATCH: whether EFFECT_CITY_ADJUST_RAZE_RATE takes effect on COLLECTION_PLAYER_CITIES. If not -> Fix B: a
# custom unit ability + grant chain (docs/RAZING-PLAN.md).]
function M-RazeRate($sfx,$amt) {
    "`t<Modifier id=`"MA_${sfx}_RAZE_RATE`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_RAZE_RATE`">$NL`t`t<SubjectRequirements>$NL$(Settle ($tallCap+1) $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# Item 3a: +flat plunder per building your units pillage (COLLECTION_OWNER, per Sayyida EFFECT_ADD_PLAYER_UNITS_PILLAGE_BUILDING_PLUNDER).
function M-RazePillageFlat($sfx,$plunder,$amt) {
    "`t<Modifier id=`"MA_${sfx}_RAZE_PILLAGE_$plunder`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_ADD_PLAYER_UNITS_PILLAGE_BUILDING_PLUNDER`">$NL`t`t<SubjectRequirements>$NL$(Settle ($tallCap+1) $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"PlunderType`">$plunder</Argument>$NL`t</Modifier>"
}
# OwnerRequirements with the node gate (skipped in -Test) + the <4-settlement anti-wide, player-scoped. For
# player-rooted collections (units/districts/combat) where a player-settlement SubjectRequirement wouldn't
# resolve. Same shape M-CombatStrength builds inline.
function OwnerNodeAntiWide($node,$minDepth=1) {
    $reqs=@()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE`"><Argument name=`"ProgressionTreeNodeType`">$node</Argument><Argument name=`"MinDepth`">$minDepth</Argument></Requirement>" }
    $reqs += (Settle $tallCap $true 'false' '')
    "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
}
# SUZERAIN-DEFERRED (Phase 3 follow-ups, now that the suzerain layer exists). Two base effects that scale a
# reward with how many city-states you are Suzerain of - the tall width-substitute, self-scaling (0 without the
# relevant suzerain), anti-wide gated, delivered through the attach wrapper. (1) Trade-route RANGE per ECONOMIC
# suzerain (EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE_PER_SUZERAIN_OF; base ATTACH_LAND_TRADE_ROUTE_RANGE_SUZERAIN:
# DomainType, Amount, CityStateType=ECONOMIC) - ties the isolated city's reach to holding economic city-states,
# the deferred M-TradeRange follow-up. (2) Resource CAPACITY per TOTAL suzerain (EFFECT_CITY_ADJUST_RESOURCE_CAP_
# PER_SUZERAIN; base MOD_SHAWNEE_CITY_STATE_RESOURCES: Amount) - more assignable resources (=> +GDP) the more
# city-states you lead. Both COLLECTION_PLAYER_CITIES (so both hemispheres' cities get it).
function M-SuzerainTradeRange($sfx,$domainType,$csType,$amt) {
    $dn = ($domainType -replace '^DOMAIN_','')
    "`t<Modifier id=`"MA_${sfx}_SUZ_RANGE_${dn}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE_PER_SUZERAIN_OF`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"DomainType`">$domainType</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"CityStateType`">$csType</Argument>$NL`t</Modifier>"
}
function M-SuzerainResourceCap($sfx,$amt) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_RESOURCE_CAP`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_RESOURCE_CAP_PER_SUZERAIN`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}

# (2) CLAIM-CHARGE GRANT (Antiquity + Exploration ONLY - Modern's base game already binds this to ABILITY_CLAIM_
#     RESOURCE via PROSPECTOR_MOD_GRANT_ABILITY_CHARGE, so re-adding it there would collide). Mirror of the base
#     PROSPECTOR_MOD_GRANT_ABILITY_CHARGE: gives 1 charge of CHARGED_ABILITY_CLAIM_RESOURCE. Bound to the ability
#     via the UnitAbilityModifiers row in surveyor-bind.xml - NOT the attach wrapper (so it is NOT in $wrapIds).
function M-GrantClaimCharge($sfx) {
    "`t<Modifier id=`"MA_${sfx}_GRANT_CLAIM_CHARGE`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_GRANT_UNIT_ABILITY_CHARGE`" permanent=`"true`">$NL`t`t<Argument name=`"ChargedAbilityType`">CHARGED_ABILITY_CLAIM_RESOURCE</Argument>$NL`t`t<Argument name=`"Amount`">$surveyorCharges</Argument>$NL`t</Modifier>"
}

$pillarManifest = [ordered]@{}   # sfx -> Triumph-window pillar ids (handed to gen-ascendancy's feat rewards)
foreach ($age in $ages) {
    $sfx=$age.Sfx; $node=$age.Node; $pops=$age.Pops; $N=$age.Nodes
    # Secondary-layer tall cap (Suzerain streams / town-spec / trade / unlocks / wonder-appeal / reseed):
    # GEN-2 RE-CUT 2026-07-19 - the old 1-per-hemisphere cap (2/3) wrongly cut this whole layer off in
    # legal 2-3 settlement empires. Now = the AGE MAX + 1 ("fewer than max+1" = within the age's ceiling:
    # AQ <=2, EX <=3, MO <=4). Deliberately LENIENT (age max, not exact earned allowance): this layer is
    # binary/static-world pieces (unlocks, appeal radiation, per-suzerain streams) that must not blink;
    # the exact-allowance windows live on the yield pillars (PillarWindows). The specialist CAP + the 2
    # safety nets keep their separate lenient non-revoking gate (Settle 4/5 'true').
    $tallCap = @{ 'AQ' = 3; 'EX' = 4; 'MO' = 5 }[$sfx]
    # NONE for AQ (no Distant Lands); HL (+ DL) for EX/MO.
    $hemis = if ($age.Distant) { @('HL','DL') } else { @('NONE') }

    $out = @()
    $out += '<?xml version="1.0" encoding="utf-8"?>'
    $out += "<!-- Metropolis Ascendant - $($age.AgeName) modifiers. GENERATED by tools/gen-ascendant.ps1 - do not hand-edit.$(if($TestMode){' [TEST BUILD: pop thresholds 2/4/6, tech gate removed - for fast validation only]'})"
    $out += "     GEN-2 EARNED-ALLOWANCE model (2026-07-19): the pillar family (Arcadia rural/peaks/waters,"
    $out += "     wonder-happiness, mountain/water adjacency, coastal floor) is WINDOWED on total settlements"
    $out += "     vs the earned allowance - _W1 = the Age floor, _W2+ = the charter-Triumph slots - exactly"
    $out += "     matching the Ascendancy tree's gate. Copies are mutually exclusive; each pays in EVERY"
    $out += "     settlement (towns count; no hemisphere twins). The secondary layer (suzerain streams,"
    $out += "     unlocks, wonder-appeal) keeps a lenient age-max gate; the specialist safety nets count"
    $out += "     CITIES ONLY with a non-revoking gate so a slip never strands specialists."
    $out += "     TECH-NODE GATE: every reward + cap gates on $($age.Node) (MinDepth=1, REQUIRED or it silently"
    $out += "     never fires). The 2 safety nets are ungated (always-on via the GameModifiers binding). -->"
    $out += '<GameEffects xmlns="GameEffects">'
    $out += ''
    # DISCOVERABILITY MARKERS (per-domain when fanned out): one no-op modifier per gated tree node, shown on
    # that node's panel via a ProgressionTreeNodeUnlocks (KIND_MODIFIER) row in traditions.xml. AQ emits one
    # per domain node (Writing/Mathematics/Masonry/Currency/Bronze Working); EX/MO emit the single host note.
    # EFFECT_PLAYER_ADJUST_SETTLEMENT_CAP Amount=0 = deliberate no-op. NOT in the attach wrapper.
    $out += "`t<!-- DISCOVERABILITY MARKERS: one no-op note modifier per gated node (see traditions.xml rows). -->"
    foreach ($note in $age.Notes) {
        if ($gen2StrippedNoteKeys -contains $note.Key) { continue }   # bonus migrated to the Ascendancy tree - no base-node panel note
        $noteId  = if ($note.Key -eq 'ALL') { "MA_${sfx}_UNLOCK_NOTE" } else { "MA_${sfx}_NOTE_$($note.Key)" }
        $noteLoc = if ($note.Key -eq 'ALL') { 'LOC_MA_UNLOCK_NOTE' }     else { "LOC_MA_${sfx}_NOTE_$($note.Key)" }   # per-age tag so EX/MO numbers differ from AQ
        $out += "`t<Modifier id=`"$noteId`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_SETTLEMENT_CAP`" permanent=`"true`">$NL`t`t<Argument name=`"Amount`">0</Argument>$NL`t`t<String context=`"Description`">$noteLoc</String>$NL`t</Modifier>"
    }
    $out += ''

    $wrapIds = @()
    $pillarRewardIds = @()   # Triumph-window pillar ids -> the EXP feat reward (via the build manifest)
    foreach ($hemi in $hemis) {
        $dl = if ($hemi -eq 'DL') { '_DL' } else { '' }
        if ($hemi -eq 'HL')   { $out += "`t<!-- ===================== HOMELAND hemisphere set ===================== -->" }
        elseif ($hemi -eq 'DL'){ $out += "`t<!-- ==================== DISTANT-LANDS hemisphere set ==================== -->" }

        # TIER 1
        $out += "`t<!-- TIER 1 (Urban pop >= $($pops[0]))$(if($dl){' - distant lands'}) -->"
        $out += (M-Upkeep $sfx $pops[0] $hemi $dl);            $wrapIds += "MA_${sfx}_T1_SPECIALIST_UPKEEP${dl}"
        $out += (M-Happiness $sfx $pops[0] $age.Happiness $hemi $dl); $wrapIds += "MA_${sfx}_T1_HAPPINESS${dl}"
        # ==== THE GEN-2 PILLAR FAMILY: windowed on the EARNED ALLOWANCE, hemisphere-free.
        # Count windows live IN-LEAF (re-evaluate continuously - proven). Route='ALL' copies ride
        # ATTACH_ALL; Route='REWARD' copies are handed to gen-ascendancy (pillar-window-ids.json)
        # and attach via the age's Expansion FEAT REWARD - the only proven mid-session Triumph
        # delivery (2026-07-21 rebuild: Triumph reqs are frozen at attach everywhere else).
        # Emitted once (non-DL).
        # ⚠ STRUCTURAL TIER (2026-07-21, run-5 attempt-4 in-game proof): ACTIVATION effects must
        # NOT be windowed - the W1-off/W2-on handover at a count change processes the off first,
        # and a deactivated adjacency rule does not re-fire (the Temple-slot twin of this bug
        # evicted 4 slotted relics). Structural/capacity/activation effects = ONE copy, count
        # ceiling <= the age max ($tallCap form, the lenient unlock tier) - never blinks in legal
        # play; only crossing the age max (the punished state) drops them.
        if ($hemi -ne 'DL') {
            $structWin = @{ W = ''; R = @((Settle $tallCap $true 'false' '')) }
            # WONDER LANE C (STRUCTURAL, binary): "+1 Happiness to buildings adjacent to a Wonder".
            $out += (M-WonderHappyAdj $sfx $structWin); $wrapIds += "MA_${sfx}_WONDER_HAPPY_ADJ"
            # MOUNTAIN LANE B (STRUCTURAL): Machu-Picchu wildcard (+Cul/+Gold per adjacent mountain).
            $out += (M-MountainAdj $sfx $age.Preserve $structWin); $wrapIds += "MA_${sfx}_MTN_ADJ_CUL"; $wrapIds += "MA_${sfx}_MTN_ADJ_GOLD"
            # WATER Option 1 (STRUCTURAL): +Gold per adjacent Coast, +Production per adjacent Navigable River.
            $out += (M-WaterAdj $sfx $age.Preserve $structWin); $wrapIds += "MA_${sfx}_WATER_ADJ_GOLD"; $wrapIds += "MA_${sfx}_WATER_ADJ_PROD"
            foreach ($w in (PillarWindows $sfx)) {
                $winIds = @()
                # WONDER LANE B2 = ARCADIA (YIELDS): Breathtaking RURAL ring, +$($age.Preserve) of the 5-set.
                $out += (M-AppealYield $sfx $age.Preserve $w $age.MtnDedup); $winIds += "MA_${sfx}_APPEAL_YIELD$($w.W)"
                # WONDER LANE M3 = Arcadia PEAKS: full 5-set on worked MOUNTAIN tiles.
                $out += (M-MountainYield $sfx $age.Preserve $w); $winIds += "MA_${sfx}_MOUNTAIN_YIELD$($w.W)"
                # ARCADIA EMBRACES THE WATERS: per-water-type worked-tile yields.
                foreach ($wtKey in $waterTypes.Keys) {
                    $out += (M-WaterYield $sfx $wtKey $waterTypes[$wtKey] $w); $winIds += "MA_${sfx}_WATER_${wtKey}_YIELD$($w.W)"
                }
                # WATER Option 4: Tonga-style coastal FLOOR (no discovery gate - pays from turn 1).
                $out += (M-WaterFloor $sfx $waterFloorAmt[$sfx] $w); $winIds += "MA_${sfx}_WATER_FLOOR_FOOD$($w.W)"; $winIds += "MA_${sfx}_WATER_FLOOR_PROD$($w.W)"
                if ($w.Route -eq 'REWARD') { $pillarRewardIds += $winIds }
                else                        { $wrapIds += $winIds }
            }
        }
        # WONDER LANE B1 (STRUCTURAL, binary, player-wide): wonders radiate +$wonderAppealAmt Appeal.
        # Lenient age-max tall gate ($tallCap); emitted ONCE -> guard to non-DL.
        if ($hemi -ne 'DL') { $out += (M-WonderAppeal $sfx $wonderAppealAmt); $wrapIds += "MA_${sfx}_WONDER_APPEAL" }
        # WONDER LANE M3 unlock (player-wide, once): IMPROVEMENT_INCA_MOUNTAIN so peaks are workable.
        if ($hemi -ne 'DL') { $out += (M-MountainUnlock $sfx); $wrapIds += "MA_${sfx}_MOUNTAIN_UNLOCK" }
        # WATER Option 3 (EX ONLY, player-wide, once): IMPROVEMENT_HAWAII_FISHING_BOAT for workable ocean.
        if ($hemi -ne 'DL' -and $sfx -eq 'EX') { $out += (M-WaterUnlock $sfx); $wrapIds += "MA_${sfx}_WATER_UNLOCK" }

        # (Tier-2 / Tier-3 / fan-out content all migrated to the Ascendancy tree or retired pre-release -
        #  their now-empty section headers were dropped 2026-07-24, issue #22. Only the Tier-1 upkeep +
        #  happiness safety nets remain on base nodes, above.)
        $out += ''
    }

    # ---- AGE-TRANSITION RESEED (EX/MO only; player-wide, not hemisphere-scoped, emitted once) ----
    # A2 de-layer 2026-07-14 (Chris ruling): DELETE the per-pop Science+Culture age-flip bridge. Base tree -> vanilla.
    # (Was gated on the base host node; Gen-2 Ascendancy cards now carry the tall payoff. Re-open the Exploration
    #  tall gap here if playtests show a slump right after an age flip.)
    # ---- SUZERAIN LAYER (Phase 3; FanOut ages only; player-wide, emitted once) ----
    # See M-Suzerain et al.: auto-scaling PER-POP yields keyed to each suzerained CS type + a flat influence
    # primer to fund winning the first city-states. The width-substitute for a one-city empire.
    if ($age.FanOut) {
        $ba = $age.BonusAge
        $out += "`t<!-- SUZERAIN: per-pop yield keyed to holding suzerainty of each CS TYPE (gate = HAS_X_TRIBUTARIES_OF_TYPE,"
        $out += "`t     NOT the bonus pick - nothing rides the draft menu). +Influence per total suzerain (Diplomatic);"
        $out += "`t     flat Influence primer. (Free-pop removed - one-shot grant can't gate.) -->"
        foreach ($cs in $suzCity.Keys) {
            $out += (M-SuzerainPerPop $sfx $null $suzCity[$cs] $cs $suzPerPopDiv); $wrapIds += "MA_${sfx}_SUZ_${cs}"   # 2nd arg (shareBonus) vestigial: decoupled, no longer read
        }
        $out += (M-SuzerainDiplo $sfx $null $suzDiploAmt); $wrapIds += "MA_${sfx}_SUZ_DIPLOMATIC"
        # FREE-POP REMOVED 2026-06-20 (playtest: pop stayed flat). EFFECT_ADJUST_PLAYER_FREE_POLPULATION_CAPITAL_
        # ON_CITY_STATE is a ONE-SHOT grant tied to the become-suzerain event; our ELIGIBLE_CS_BONUS requirement
        # only flips true AFTER that moment, so the grant window is missed. No continuous "pop per CS" alternative
        # exists, so it can't deliver through our gating. Expansionist is covered by the per-pop Food above.
        $out += (M-Influence $sfx $suzPrimer);                                            $wrapIds += "MA_${sfx}_SUZ_PRIMER"
        # SUZERAIN-DEFERRED follow-ups: +Trade Route range per ECONOMIC suzerain (land+sea) - ties the tall
        # city's reach to holding economic city-states; +Resource capacity per TOTAL suzerain. Both self-scale.
        $out += (M-SuzerainTradeRange $sfx 'DOMAIN_LAND' 'ECONOMIC' $suzTradeRangeAmt);    $wrapIds += "MA_${sfx}_SUZ_RANGE_LAND"
        $out += (M-SuzerainTradeRange $sfx 'DOMAIN_SEA' 'ECONOMIC' $suzTradeRangeAmt);     $wrapIds += "MA_${sfx}_SUZ_RANGE_SEA"
        $out += (M-SuzerainResourceCap $sfx $suzResCapAmt);                               $wrapIds += "MA_${sfx}_SUZ_RESOURCE_CAP"
        $out += ''
    }

    # ---- RAZING LANE (issue #3; player-wide, emitted once) ----
    # "Destroy what you can't hold" for a one-city empire, WITHOUT buffing wide conquest. All effects are VISIBLE:
    # a one-time Gold + Influence LUMP per city taken by combat (folds in the old invisible Influence offset), the
    # per-building pillage reward, and a near-instant burn. All burn-tolerant tall-gated; a wide conquer-and-keep
    # empire is excluded. See M-Raze* + config header + docs/RAZING-PLAN.md.
    if ($age.FanOut) {
        $out += "`t<!-- RAZING (issue #3): make razing viable for a tall empire, all effects VISIBLE. Capture LUMP (Gold +"
        $out += "`t     Influence per city taken by combat) + per-building pillage + near-instant burn. Burn-tolerant tall gate."
        $out += "`t     (Cut as invisible/broken: Influence offset, Sci/Cul floor, ignore-unrest, war-cap, %plunder - see header.) -->"
        $out += (M-RazeCapture $sfx 'GOLD' $razeCaptureGold);                $wrapIds += "MA_${sfx}_RAZE_CAPTURE_GOLD"
        $out += (M-RazeCapture $sfx 'DIPLOMACY' $razeCaptureInf);            $wrapIds += "MA_${sfx}_RAZE_CAPTURE_DIPLOMACY"
        $out += (M-RazeRate $sfx $razeRateBonus);                            $wrapIds += "MA_${sfx}_RAZE_RATE"
        $out += (M-RazePillageFlat $sfx 'PLUNDER_GOLD' $razePillageFlat);    $wrapIds += "MA_${sfx}_RAZE_PILLAGE_PLUNDER_GOLD"
        $out += (M-RazePillageFlat $sfx 'PLUNDER_SCIENCE' $razePillageFlat); $wrapIds += "MA_${sfx}_RAZE_PILLAGE_PLUNDER_SCIENCE"
        $out += ''
    }

    # ===================== TOWN-SPECIALIZATION ROLL-IN (player-wide) =====================
    # DISTINCT LAYER from the Suzerain layer above. These internalize base-game TOWN specialization focuses
    # (a wide empire's specialized towns pipe benefits to its cities; a 1-city player has no towns, so we grant
    # the same effects to the metropolis, gated behind the relevant node). KEY RULE (avoid yield overlap): only
    # roll in buckets whose MECHANIC is NOT already covered by the fan-out kit. Buckets that duplicate an
    # existing lever are NOT re-emitted here - the existing lever IS that bucket (Trade Outpost = M-TradeRange;
    # Factory = M-ResourceCap + M-TradeRange). Player-wide buckets are emitted once here; per-hemisphere /
    # per-city town buckets (e.g. Religious Site temple slots) are emitted in the hemisphere loop, each tagged
    # "TOWN-SPEC" at its emit site. Town-spec modifier ids are descriptive (HUB_INFLUENCE, T2_TEMPLE_SLOTS).
    # See docs/TOWN-SPECIALIZATIONS.md and the civ7-modding skill's town-specialization reference.
    # TOWN-SPECIALIZATION ROLL-IN: every bucket (Hub influence, the Fort kit, the three warehouses,
    # Religious-Site happiness, the Resort pair) was retired pre-release; its emitted section header was
    # dropped 2026-07-24 (issue #22). See docs/TOWN-SPECIALIZATIONS.md for what each did and where its
    # Ascendancy-tree replacement lives.

    # ---- SURVEYOR once-block (issue #12): claim-charge grant (AQ/EX only) ----
    # NO per-resource amplifier (2026-07-02): a claimed resource keeps its normal base yields only. Arcadia's
    # Breathtaking / mountain / water bonuses already enrich worked tiles, and stacking a per-resource amplifier on top
    # would overpower a single tile. The Surveyor's tall-exclusive value is the REACH itself (pull ring-4/5 resources
    # into the one metropolis), not extra yield. (M-ResourceReach + the $resYields reader are retained but unused.)
    if ($age.FanOut) {
        $out += "`t<!-- SURVEYOR (issue #12): the CLAIM_RESOURCE charge-grant modifier (Antiquity + Exploration only - Modern's base"
        $out += "`t     game already binds it) is bound to ABILITY_CLAIM_RESOURCE via surveyor-bind.xml, NOT the attach wrapper. -->"
        if ($sfx -ne 'MO') { $out += (M-GrantClaimCharge $sfx) }   # deliberately absent from $wrapIds (UnitAbility-bound)
        $out += ''
    }

    # (ADJACENCY REWARD block removed 2026-07-24, issue #22: $adjRules was emptied when the base-node
    #  adjacency lane moved onto the Ascendancy tree, so the loop emitted only empty tier headers. The
    #  block plus its now-orphan helpers - M-Adjacency, $adjRules/$bandList/$adjDiv/$ruleDomain - are gone.)

    # ---- victory-wonder recycle convert modifiers (MODERN only; bound to the Foundations buildings in recycle.xml) ----
    if ($age.Key -eq 'modern') {
        $out += "`t<!-- VICTORY-WONDER RECYCLE (issue #1): each MO 'Foundations' building (data/modern/recycle.xml) overbuilds an"
        $out += "`t     obsolete district; on completion its ConstructibleModifier below REPLACE-converts it into its victory Wonder"
        $out += "`t     on that tile. COLLECTION_OWNER + run-once, bound via <ConstructibleModifiers> (NOT the attach wrapper, so these"
        $out += "`t     are intentionally absent from MA_MO_ATTACH_ALL). Gated tall + not-already-owned; the building's unlock-node gate"
        $out += "`t     (recycle.xml) keeps it tile-relief, never a victory shortcut. -->"
        foreach ($r in $recycle) { $out += (M-Reclaim $r) }
        $out += ''
    }

    # ---- ATTACH_ALL delivery wrapper ----
    $out += "`t<!-- DELIVERY WRAPPER: a COLLECTION_PLAYER_CITIES modifier bound directly via GameModifiers never"
    $out += "`t     attaches (game-level has no `"the player`" context). The base game wraps player bonuses in a"
    $out += "`t     COLLECTION_MAJOR_PLAYERS + EFFECT_ATTACH_MODIFIERS modifier; traditions.xml binds ONLY this"
    $out += "`t     wrapper, which attaches every modifier below to each major player so they resolve their own"
    $out += "`t     collection + tech-node + pop + per-hemisphere anti-wide gates. -->"
    $out += "`t<Modifier id=`"MA_${sfx}_ATTACH_ALL`" collection=`"COLLECTION_MAJOR_PLAYERS`" effect=`"EFFECT_ATTACH_MODIFIERS`">"
    $out += "`t`t<Argument name=`"ModifierId`">$($wrapIds -join ', ')</Argument>"
    $out += "`t</Modifier>"
    $pillarManifest[$sfx] = $pillarRewardIds   # -> tools/pillar-window-ids.json for gen-ascendancy's feat rewards
    $out += ''
    $out += '</GameEffects>'

    $file = Join-Path $root "$($age.Key)\modifiers.xml"
    $text = ($out -join $NL)
    Set-Content -LiteralPath $file -Value $text -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $file -Raw) | Out-Null   # validate or throw
    $mods = (Select-String -LiteralPath $file -Pattern '<Modifier id=' -SimpleMatch).Count
    Write-Host "$($age.Key): valid | $mods modifiers | $($wrapIds.Count) in ATTACH_ALL"

    # ---- GENERATED traditions.xml (bindings) ----
    # Single source of truth = $age.Notes. The GameModifiers row binds ONLY the attach wrapper; the
    # ProgressionTreeNodeUnlocks rows advertise each gated slice on its node's panel. A note's Depth (default 1)
    # becomes UnlockDepth, so a MASTERY-gated bonus (MinDepth=2, e.g. Resort) lands on the node's MASTERY panel
    # instead of the base unlock. Regenerating here keeps marker / text / unlock-row / gate-depth from drifting.
    $tr2 = @('<?xml version="1.0" encoding="utf-8"?>')
    $tr2 += "<!-- Metropolis Ascendant - $($age.AgeName) bindings. GENERATED by tools/gen-ascendant.ps1 - do not"
    $tr2 += "     hand-edit. Source of truth = the `$ages Notes array. GameModifiers binds only the attach wrapper"
    $tr2 += "     (MA_${sfx}_ATTACH_ALL); each bonus self-gates on node + population + anti-wide in modifiers.xml."
    $tr2 += "     ProgressionTreeNodeUnlocks rows are display-only and advertise each slice on its node panel"
    $tr2 += "     (UnlockDepth comes from each note's Depth: 1 = base unlock, 2 = the node's Mastery panel). -->"
    $tr2 += '<Database>'
    $tr2 += "`t<GameModifiers>"
    $tr2 += "`t`t<Row ModifierId=`"MA_${sfx}_ATTACH_ALL`"/>"
    $tr2 += "`t</GameModifiers>"
    $tr2 += "`t<ProgressionTreeNodeUnlocks>"
    foreach ($note in $age.Notes) {
        if ($gen2StrippedNoteKeys -contains $note.Key) { continue }   # bonus migrated to the Ascendancy tree - no base-node panel note
        $noteId = if ($note.Key -eq 'ALL') { "MA_${sfx}_UNLOCK_NOTE" } else { "MA_${sfx}_NOTE_$($note.Key)" }
        $depth  = if ($note.Depth) { $note.Depth } else { 1 }
        $tr2 += "`t`t<Row ProgressionTreeNodeType=`"$($note.Node)`" TargetKind=`"KIND_MODIFIER`" TargetType=`"$noteId`" UnlockDepth=`"$depth`"/>"
    }
    $tr2 += "`t</ProgressionTreeNodeUnlocks>"
    $tr2 += '</Database>'
    $trFile = Join-Path $root "$($age.Key)\traditions.xml"
    Set-Content -LiteralPath $trFile -Value (($tr2 -join $NL)) -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $trFile -Raw) | Out-Null   # validate or throw
    $rows = (Select-String -LiteralPath $trFile -Pattern '<Row ProgressionTreeNodeType=' -SimpleMatch).Count
    Write-Host "$($age.Key): traditions valid | $rows unlock rows"

    # ---- GENERATED data/<age>/surveyor.xml (issue #12: the Surveyor unit + claim-ability plumbing + unlock) ----
    # Loaded in the SHARED action group (LoadOrder 105, BEFORE modifiers.xml at 110) so the grant-unit + amplifier
    # modifiers can reference UNIT_MA_SURVEYOR. The claim-ability chain (ABILITY_CLAIM_RESOURCE type, UNIT_CLASS_
    # PROSPECTOR tag, UnitClass_Abilities/UnitAbilities/ChargedUnitAbilities) is Modern-only in the base game, so it
    # is emitted for AQ/EX and OMITTED for MO (which already has it - re-adding would duplicate-insert and crash).
    $isMO = ($age.Key -eq 'modern')
    # 3D-model donor + flag icon for the Surveyor (no art of its own -> renders empty without a VisualRemap + icon).
    # UNIFORM SCOUT across ALL ages (2026-07-02, forced by engine constraint): icons AND VisualRemaps register
    # only from criteria="always" action groups (age-modern loads its own via always groups; our per-age groups showed
    # a BLACK portrait in-game). A single-module mod therefore CANNOT differ the look per Age - one global look only.
    # UNIT_SCOUT + blp:unitflag_scout live in base-standard (always loaded), so the Scout renders in every Age incl.
    # Modern. (Prospector-in-Modern was the intent but its art is age-modern-only AND per-age groups don't register.)
    # Donor = MIGRANT (Chris's final call 2026-07-13 — a Settler-wagon donor was tried and REJECTED same day;
    # the Migrant stays). Known accepted limitations: VisualRemaps have NO age column and NO scale knob (one
    # global look), so the Migrant's figures read the same in every Age and can't be enlarged. Civilian model
    # reads as a "surveyor"; self-consuming charge mirrors the one-shot claim; base-standard = renders every Age.
    $surveyorDonor    = 'UNIT_MIGRANT'
    # 2026-07-12: custom compass-rose glyph (hand-authored PNGs in ui/icons/, ImportFiles'd in BOTH scopes in the
    # modinfo) replaces the borrowed Migrant blps - distinguishes the Surveyor's flag/build-list icon from real
    # Migrants. The selected-unit panel portrait is separately fixed by ui/surveyor/mad-surveyor-portrait.js
    # (UIScripts decorator repointing the live 3D render at the donor). Donor model unchanged (Migrant).
    $surveyorFlag     = 'fs://game/metropolis-ascendant/ui/icons/surveyor-flag.png'      # default-context row = map flag / small unit icon
    $surveyorPortrait = 'fs://game/metropolis-ascendant/ui/icons/surveyor-portrait.png'  # FONTICON row = larger portrait in build/list panels
    $su = @('<?xml version="1.0" encoding="utf-8"?>')
    $su += "<!-- Metropolis Ascendant - $($age.AgeName) Surveyor (issue #12). GENERATED by tools/gen-ascendant.ps1 - do not hand-edit."
    $su += '     The Surveyor is a civilian carrying the base Prospector CLAIM_RESOURCE command (tagged UNIT_CLASS_PROSPECTOR).'
    if ($isMO) { $su += '     MODERN: only the unit + tag + unlock (base already defines the ability chain).' }
    else       { $su += '     ANTIQUITY/EXPLORATION: also registers the claim-ability chain the base game only ships in Modern. -->' }
    if ($isMO) { $su += '-->' }
    $su += '<Database>'
    $su += "`t<Types>"
    $su += "`t`t<Row Type=`"$surveyorUnit`" Kind=`"KIND_UNIT`"/>"
    if (-not $isMO) { $su += "`t`t<Row Type=`"ABILITY_CLAIM_RESOURCE`" Kind=`"KIND_ABILITY`"/>" }
    $su += "`t</Types>"
    if (-not $isMO) {
        $su += "`t<Tags>"
        $su += "`t`t<Row Tag=`"UNIT_CLASS_PROSPECTOR`" Category=`"UNIT_CLASS`"/>"
        $su += "`t</Tags>"
    }
    $su += "`t<Units>"
    $su += "`t`t<Row UnitType=`"$surveyorUnit`" Name=`"LOC_UNIT_MA_SURVEYOR_NAME`" Description=`"LOC_UNIT_MA_SURVEYOR_DESCRIPTION`" BaseSightRange=`"1`" BaseMoves=`"$surveyorMoves`" UnitMovementClass=`"UNIT_MOVEMENT_CLASS_FOOT`" Domain=`"DOMAIN_LAND`" CoreClass=`"CORE_CLASS_CIVILIAN`" FormationClass=`"FORMATION_CLASS_SUPPORT`" ZoneOfControl=`"false`" CostProgressionModel=`"COST_PROGRESSION_PREVIOUS_COPIES`" CostProgressionParam1=`"20`"/>"
    $su += "`t</Units>"
    $su += "`t<Unit_Costs>"
    $su += "`t`t<Row UnitType=`"$surveyorUnit`" YieldType=`"YIELD_PRODUCTION`" Cost=`"$($surveyorCost[$sfx])`"/>"
    $su += "`t</Unit_Costs>"
    $su += "`t<TypeTags>"
    $su += "`t`t<Row Type=`"$surveyorUnit`" Tag=`"UNIT_CLASS_PROSPECTOR`"/>"
    $su += "`t</TypeTags>"
    # (VISUAL: the Surveyor's VisualRemap is NOT here - VisualRemaps is not a gameplay-DB table, so it CANNOT load via
    #  UpdateDatabase like this file ("no such table: VisualRemaps" crash). It is emitted to surveyor-visualremap.xml
    #  below and loaded via a dedicated <UpdateVisualRemaps> action in the modinfo - see that file's generation.)
    if (-not $isMO) {
        $su += "`t<UnitClass_Abilities>"
        $su += "`t`t<Row UnitAbilityType=`"ABILITY_CLAIM_RESOURCE`" UnitClassType=`"UNIT_CLASS_PROSPECTOR`"/>"
        $su += "`t</UnitClass_Abilities>"
        $su += "`t<UnitAbilities>"
        $su += "`t`t<Row UnitAbilityType=`"ABILITY_CLAIM_RESOURCE`" Name=`"LOC_MA_SURVEYOR_CLAIM_NAME`" Description=`"LOC_MA_SURVEYOR_CLAIM_DESCRIPTION`"/>"
        $su += "`t</UnitAbilities>"
        $su += "`t<ChargedUnitAbilities>"
        $su += "`t`t<Row UnitAbilityType=`"CHARGED_ABILITY_CLAIM_RESOURCE`" RechargeTurns=`"$surveyorRecharge`"/>"
        $su += "`t</ChargedUnitAbilities>"
    }
    # NO ProgressionTreeNodeUnlocks: like the base Scout/Settler (which have no unlock row), a unit with no tech gate is
    # BUILDABLE from the start of the Age - and, crucially, a locked unit can't be GRANTED, so gating it on Currency broke
    # the Antiquity pop-milestone grants (2026-07-02 in-game: nothing spawned at pop 5, unit showed blocked by Currency).
    # It carries no AI advisory hints, so the AI won't spam it; the tall-exclusive value is the AQ grants + the amplifier
    # (both tall-gated). The per-resource amplifier still unlocks on the Economic node (a modifier gate, not a unit gate).
    $su += '</Database>'
    $suFile = Join-Path $root "$($age.Key)\surveyor.xml"
    Set-Content -LiteralPath $suFile -Value (($su -join $NL)) -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $suFile -Raw) | Out-Null   # validate or throw
    Write-Host "$($age.Key): surveyor.xml valid$(if($isMO){' (Modern: unit+tag+unlock only)'}else{' (AQ/EX: full ability chain)'})"

    # ---- GENERATED data/surveyor-visualremap.xml (ONCE, GLOBAL - loaded via a dedicated <UpdateVisualRemaps> action in
    #      the criteria="always" group, NOT UpdateDatabase - VisualRemaps is a separate visual-layer DB; UpdateDatabase
    #      crashes "no such table: VisualRemaps"). GLOBAL (not per-age) because VisualRemaps register ONLY from always
    #      groups (per-age groups don't register). Donor art = UNIT_SCOUT (base-standard, renders every Age).
    #      🔑 DIRECTION (base REMAP_SCOUT_FOUNDER = From UNIT_SCOUT -> To UNIT_SCOUT_FOUNDER; PALACE -> PALACE_FOUNDER):
    #      From = DONOR art (real unit whose model exists), To = the REQUESTED identity (our new unit). The selected-unit
    #      PORTRAIT is a LIVE 3D render (unit-actions.js: WorldUI.requestPortrait + `live:/UNIT_MA_SURVEYOR`), so a
    #      modelless unit shows a BLACK portrait + empty map model until this remap points our unit at the Scout art. -->
    if ($age.Key -eq 'antiquity') {
        $vr = @('<?xml version="1.0" encoding="utf-8"?>')
        $vr += "<!-- Metropolis Ascendant - Surveyor visual remap (issue #12). GENERATED. Renders UNIT_MA_SURVEYOR using $surveyorDonor art in every Age. -->"
        $vr += '<Database>'
        $vr += "`t<VisualRemaps>"
        $vr += "`t`t<Row>"
        $vr += "`t`t`t<ID>REMAP_MA_SURVEYOR</ID>"
        $vr += "`t`t`t<DisplayName>LOC_UNIT_MA_SURVEYOR_NAME</DisplayName>"
        $vr += "`t`t`t<Kind>UNIT</Kind>"
        $vr += "`t`t`t<From>$surveyorDonor</From>"
        $vr += "`t`t`t<To>$surveyorUnit</To>"
        $vr += "`t`t</Row>"
        $vr += "`t</VisualRemaps>"
        $vr += '</Database>'
        $vrFile = Join-Path $root 'surveyor-visualremap.xml'
        Set-Content -LiteralPath $vrFile -Value (($vr -join $NL)) -NoNewline -Encoding UTF8
        [xml](Get-Content -LiteralPath $vrFile -Raw) | Out-Null   # validate or throw
        Write-Host "surveyor-visualremap.xml valid (-> $surveyorDonor, global)"
    }

    # ---- GENERATED data/<age>/surveyor-bind.xml (loads at 110, AFTER modifiers.xml) ----
    # AQ/EX: bind ABILITY_CLAIM_RESOURCE -> the charge-grant modifier (defined in modifiers.xml, this age group, above).
    # MO: optionally force CHARGED_ABILITY_CLAIM_RESOURCE to one-shot to match AQ/EX (Update on the base row).
    $sb = @('<?xml version="1.0" encoding="utf-8"?>')
    $sb += "<!-- Metropolis Ascendant - $($age.AgeName) Surveyor bindings (issue #12). GENERATED - do not hand-edit."
    $sb += '     Loads after modifiers.xml so the UnitAbilityModifiers FK to the charge-grant modifier resolves. -->'
    $sb += '<Database>'
    if (-not $isMO) {
        $sb += "`t<UnitAbilityModifiers>"
        $sb += "`t`t<Row UnitAbilityType=`"ABILITY_CLAIM_RESOURCE`" ModifierId=`"MA_${sfx}_GRANT_CLAIM_CHARGE`"/>"
        $sb += "`t</UnitAbilityModifiers>"
    } elseif ($surveyorOverrideModernRecharge) {
        $sb += "`t<ChargedUnitAbilities>"
        $sb += "`t`t<Update><Where UnitAbilityType=`"CHARGED_ABILITY_CLAIM_RESOURCE`"/><Set RechargeTurns=`"$surveyorRecharge`"/></Update>"
        $sb += "`t</ChargedUnitAbilities>"
    }
    $sb += '</Database>'
    $sbFile = Join-Path $root "$($age.Key)\surveyor-bind.xml"
    Set-Content -LiteralPath $sbFile -Value (($sb -join $NL)) -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $sbFile -Raw) | Out-Null   # validate or throw
    Write-Host "$($age.Key): surveyor-bind.xml valid"

    # ---- GENERATED data/icons/surveyor-icons.xml (ONCE, GLOBAL - loaded via <UpdateIcons> in the criteria="always"
    #      group, like recycle-icons). GLOBAL not per-age: the icon manager registers icons ONLY from always groups
    #      (age-modern loads its own unit-icons via always groups; our per-age groups gave a BLACK portrait in-game).
    #      One flag (blp:unitflag_scout, base-standard = every Age). The build-panel portrait uses this default-context
    #      IconDefinitions row (the base Prospector shows fine with only its unitflag + no fonticon, proving that). -->
    if ($age.Key -eq 'antiquity') {
        # Two rows, mirroring the base Scout's FULL icon footprint (unit-icons.xml + text-icons.xml): the default-context
        # row = the map/flag icon (blp:unitflag_scout); the FONTICON row = the larger PORTRAIT the selected-unit + build
        # panels show (blp:fi_unit_scout_64). We only had the flag before -> the portrait square was BLACK. Both reuse
        # base-standard Scout blps (present every Age). $surveyorFlag = unitflag_scout, $surveyorPortrait = fi_unit_scout_64.
        $si = @('<?xml version="1.0" encoding="utf-8"?>')
        $si += "<!-- Metropolis Ascendant - Surveyor icon (issue #12). GENERATED. Custom compass-rose glyph (ui/icons/, ImportFiles both scopes):"
        $si += "     Flag=$surveyorFlag, Portrait=$surveyorPortrait. -->"
        $si += '<Database>'
        $si += "`t<IconDefinitions>"
        $si += "`t`t<Row><ID>$surveyorUnit</ID><Path>$surveyorFlag</Path></Row>"
        $si += "`t`t<Row ID=`"$surveyorUnit`" Context=`"FONTICON`" IconSize=`"64`" Path=`"$surveyorPortrait`" />"
        $si += "`t</IconDefinitions>"
        $si += '</Database>'
        $siDir = Join-Path $root 'icons'
        if (-not (Test-Path $siDir)) { New-Item -ItemType Directory -Force -Path $siDir | Out-Null }
        $siFile = Join-Path $siDir 'surveyor-icons.xml'
        Set-Content -LiteralPath $siFile -Value (($si -join $NL)) -NoNewline -Encoding UTF8
        [xml](Get-Content -LiteralPath $siFile -Raw) | Out-Null
        Write-Host "surveyor-icons.xml valid ($surveyorFlag, global)"
    }

    # ---- GENERATED data/modern/recycle.xml (victory-wonder "Foundations" buildings + unlock rows + bindings) ----
    # MODERN only. Defines each Foundations BUILDING and binds its convert Modifier (MA_MO_RECLAIM_*, emitted into
    # modifiers.xml above, which loads first in the modern action group). Loaded by a <Item>data/modern/recycle.xml</Item>
    # in the modinfo's modern ActionGroup (after modifiers.xml so the ConstructibleModifiers FK resolves).
    if ($age.Key -eq 'modern') {
        $rc = @('<?xml version="1.0" encoding="utf-8"?>')
        $rc += '<!-- Metropolis Ascendant - victory-wonder recycle "Foundations" buildings. GENERATED by tools/gen-ascendant.ps1 -'
        $rc += '     do not hand-edit (source of truth = the $recycle config). Each BUILDING overbuilds an obsolete district; its'
        $rc += '     ConstructibleModifier (MA_MO_RECLAIM_*, in modifiers.xml) REPLACE-converts it into the victory Wonder on'
        $rc += '     completion. Gated on the wonder''s own unlock node (TargetKind=KIND_CONSTRUCTIBLE below) + tall + not-owned. -->'
        $rc += '<Database>'
        $rc += "`t<Types>"
        foreach ($r in $recycle) { $rc += "`t`t<Row Type=`"$($r.Building)`" Kind=`"KIND_CONSTRUCTIBLE`"/>" }
        $rc += "`t</Types>"
        $rc += "`t<Constructibles>"
        foreach ($r in $recycle) { $rc += "`t`t<Row ConstructibleType=`"$($r.Building)`" Name=`"LOC_MA_RECLAIM_$($r.Loc)_NAME`" Description=`"LOC_MA_RECLAIM_$($r.Loc)_DESCRIPTION`" Tooltip=`"LOC_MA_RECLAIM_$($r.Loc)_TOOLTIP`" ConstructibleClass=`"BUILDING`" Cost=`"$($r.Cost)`" Population=`"0`" Age=`"AGE_MODERN`" RequiresUnlock=`"true`"/>" }
        $rc += "`t</Constructibles>"
        $rc += "`t<Buildings>"
        foreach ($r in $recycle) { $rc += "`t`t<Row ConstructibleType=`"$($r.Building)`" Movable=`"false`"/>" }   # no Town attr = city-only
        $rc += "`t</Buildings>"
        $rc += "`t<Constructible_ValidDistricts>"
        foreach ($r in $recycle) { $rc += "`t`t<Row ConstructibleType=`"$($r.Building)`" DistrictType=`"DISTRICT_URBAN`"/>" }   # overbuilds obsolete urban districts
        $rc += "`t</Constructible_ValidDistricts>"
        $rc += "`t<ProgressionTreeNodeUnlocks>"
        foreach ($r in $recycle) { $rc += "`t`t<Row ProgressionTreeNodeType=`"$($r.Node)`" TargetKind=`"KIND_CONSTRUCTIBLE`" TargetType=`"$($r.Building)`" UnlockDepth=`"$($r.Depth)`"/>" }   # gated on the wonder's OWN unlock
        $rc += "`t</ProgressionTreeNodeUnlocks>"
        $rc += "`t<ConstructibleModifiers>"
        foreach ($r in $recycle) { $rc += "`t`t<Row ConstructibleType=`"$($r.Building)`" ModifierId=`"MA_MO_RECLAIM_$($r.Loc)`"/>" }
        $rc += "`t</ConstructibleModifiers>"
        $rc += '</Database>'
        $rcFile = Join-Path $root 'modern\recycle.xml'
        Set-Content -LiteralPath $rcFile -Value (($rc -join $NL)) -NoNewline -Encoding UTF8
        [xml](Get-Content -LiteralPath $rcFile -Raw) | Out-Null   # validate or throw
        Write-Host "modern: recycle.xml valid | $($recycle.Count) Foundations buildings"

        # Icons: map each Foundations building to its target Wonder's icon (so it reads as that Wonder in the build UI).
        # Loaded via an <UpdateIcons> action group in the modinfo (NOT UpdateDatabase - icons use the icon DB).
        $ic = @('<?xml version="1.0" encoding="utf-8"?>')
        $ic += '<!-- Metropolis Ascendant - icons for the victory-wonder "Foundations" buildings. GENERATED by'
        $ic += '     tools/gen-ascendant.ps1. Each reuses its target Wonder''s blp icon (no custom art). -->'
        $ic += '<Database>'
        $ic += "`t<IconDefinitions>"
        foreach ($r in $recycle) { $ic += "`t`t<Row><ID>$($r.Building)</ID><Path>$($r.Icon)</Path></Row>" }
        $ic += "`t</IconDefinitions>"
        $ic += '</Database>'
        $icDir = Join-Path $root 'icons'
        if (-not (Test-Path $icDir)) { New-Item -ItemType Directory -Path $icDir | Out-Null }
        $icFile = Join-Path $icDir 'recycle-icons.xml'
        Set-Content -LiteralPath $icFile -Value (($ic -join $NL)) -NoNewline -Encoding UTF8
        [xml](Get-Content -LiteralPath $icFile -Raw) | Out-Null   # validate or throw
        Write-Host "modern: recycle-icons.xml valid | $($recycle.Count) icon rows"
    }
}

# ---- BUILD MANIFEST: pillar Triumph-window ids -> gen-ascendancy (2026-07-21 delivery rebuild) ----
# The pillar REWARD windows (AQ/EX _W2, MO _W3) must attach at Triumph-completion time, and the only
# proven mid-session Triumph delivery is the Expansion feat's reward attach - which gen-ascendancy
# owns. publish.ps1 runs this script FIRST, so the manifest is always fresh when gen-ascendancy reads it.
$pillarManifestFile = Join-Path $PSScriptRoot 'pillar-window-ids.json'
$pillarManifest | ConvertTo-Json | Set-Content -LiteralPath $pillarManifestFile -Encoding UTF8
Write-Host "pillar-window-ids.json: $((($pillarManifest.Keys | ForEach-Object { "$_=$(@($pillarManifest[$_]).Count)" }) -join ' '))"

# ---- GENERATED discoverability note TEXT (PER AGE, specific numbers, always in sync with the config) ----
# Each tech/civic panel's "unlocked" line states the ACTUAL values for THAT age (Wonder %, slots, etc. differ
# between Antiquity / Exploration / Modern), so retuning a number updates the in-game text on the next run.
# Tags are per-age (LOC_MA_<SFX>_NOTE_<KEY>) so EX no longer inherits AQ's numbers. Written to a SEPARATE
# file (the hand text must NOT define these or the rows collide). Tiers are referenced as T1/T2/T3; the
# tier -> Urban-Pop thresholds + the per-settlement cutoff are defined ONCE in the modinfo <Description>.
function Build-NoteText($a) {
    $w=$a.Wonders; $gw=$a.GW; $col=$a.Collection
    $rcA=$a.ResCap[0]; $rcB=$a.ResCap[1]; $rcC=$a.ResCap[2]; $rcCur=$rcA+$rcB; $rcTot=$rcA+$rcB+$rcC
    $tr=$a.Trade; $trg=$a.TradeRange; $ms=$a.MilStrength; $uc=$a.UnderCapAmount; $ts=$a.TempleSlots
    $ppd=$perPopDiv['SOLO']                           # per-pop SOLO divisor (=2 -> "+1 per 2 Urban Pop")
    $upop="[icon:YIELD_POPULATION] Urban Pop"         # always say URBAN population, not overall
    $sciNote  = "+1 [icon:YIELD_SCIENCE] Science adjacency per Tier (max +3)."
    $cul2Note = "+1 [icon:YIELD_CULTURE] Culture adjacency per Tier (max +3)."
    $relNote  = "+$religiousHappy [icon:YIELD_HAPPINESS] Happiness per Building, and +$gwCultureAmt [icon:YIELD_CULTURE] Culture per Great Work in this city (T2)."
    [ordered]@{
      SCIENCE  = $sciNote
      SCIENCE2 = "+1 [icon:YIELD_SCIENCE] Science per $ppd $upop (T3)."
      CULTURE  = "+$($w[0])% [icon:YIELD_PRODUCTION] Wonder Production (T2)."
      RESORT   = "+$resortAppeal [icon:YIELD_GOLD] Gold and [icon:YIELD_HAPPINESS] Happiness on Appealing tiles, and +$resortNWPercent% to all yields from tiles with a Natural Wonder."
      CULTURE2 = $cul2Note
      ECONOMIC = "+1 Specialist slot per district per Tier (max +3, Cities only); +$rcA Resource capacity (T1-T2, max +$rcCur). Specialists also cost 50% less [icon:YIELD_FOOD] Food and [icon:YIELD_HAPPINESS] Happiness to maintain until this Settlement is Ecstatic."
      STAGE_SCIENCE = "While Joyous or happier: +1 [icon:YIELD_SCIENCE] Science per $stageJoyousDiv $upop, increasing further while Ecstatic."
      STAGE_CULTURE = "While Joyous or happier: +1 [icon:YIELD_CULTURE] Culture per $stageJoyousDiv $upop, increasing further while Ecstatic."
      ECONOMIC2= "+$rcC Resource capacity (T3; +$rcTot total)."
      SURVEYOR = "Reach beyond your borders: build a [icon:YIELD_PRODUCTION] Surveyor to claim a resource up to 5 tiles from your Settlements, pulling it - with its normal yields - into your metropolis. Each Surveyor claims $surveyorCharges resource, then is spent; build more to gather resources a sprawling empire would need many cities to hold."
      TRADE    = "+$tr Trade Routes, +$trg Trade Route range (land and sea), and +[icon:YIELD_HAPPINESS] Happiness from Resources."
      MILITARY = "+1 [icon:YIELD_PRODUCTION] Production per $ppd $upop (T3)."
      MILITARY2= "+$ms Combat Strength in all combat."
      FORT     = "+$fortHealth District HP, +$fortHeal Unit healing per turn, and +$fortGold [icon:YIELD_GOLD] Gold on Fortifications."
      FOODCAP  = "+$uc [icon:YIELD_FOOD] Food per settlement under your Settlement Cap, and +[icon:YIELD_FOOD] Food on worked Farms, Pastures, Plantations and Fishing Boats."
      PRODCAP  = "+$uc [icon:YIELD_PRODUCTION] Production per settlement under your Settlement Cap, and +[icon:YIELD_PRODUCTION] Production on worked Camps, Mines, Quarries and Woodcutters."
      RELIGION = $relNote
      SUZERAIN = "Suzerainty itself feeds the metropolis: for each City-State type you are Suzerain of, your cities earn +1 of its yield per $suzPerPopDiv [icon:YIELD_POPULATION] Urban Population ([icon:YIELD_SCIENCE] Scientific, [icon:YIELD_CULTURE] Cultural, [icon:YIELD_PRODUCTION] Militaristic, [icon:YIELD_GOLD] Economic, [icon:YIELD_FOOD] Expansionist) - whichever Suzerain bonus you pick. Diplomatic Suzerainties add +$suzDiploAmt [icon:YIELD_DIPLOMACY] Influence per turn each. Each Suzerain grants +$suzResCapAmt Resource capacity; Economic ones add +$suzTradeRangeAmt Trade Route range."
    }
}
$fanAges = @($ages | Where-Object { $_.FanOut })
if ($fanAges) {
    $noteRowCount = 0
    $tl = @('<?xml version="1.0" encoding="utf-8"?>')
    $tl += '<!-- GENERATED by tools/gen-ascendant.ps1 - do not hand-edit. Per-AGE unlock notes with live'
    $tl += '     numbers from the $ages config; retune there and re-run. Hand text lives in MetropolisAscendantText.xml. -->'
    $tl += '<Database>'
    $tl += "`t<EnglishText>"
    foreach ($a in $fanAges) {
        $sfxA = $a.Sfx
        $nt = Build-NoteText $a
        foreach ($note in $a.Notes) {       # only emit the keys this age actually uses (its Notes array)
            if ($note.Key -eq 'ALL') { continue }
            if ($gen2StrippedNoteKeys -contains $note.Key) { continue }   # bonus migrated to the Ascendancy tree - no base-node panel note
            $t = $nt[$note.Key] -replace '&','&amp;' -replace '<(?![A-Za-z/])','&lt;'
            $tl += "`t`t<Row Tag=`"LOC_MA_${sfxA}_NOTE_$($note.Key)`">"
            $tl += "`t`t`t<Text>$t</Text>"
            $tl += "`t`t</Row>"
            $noteRowCount++
        }
    }
    $tl += "`t</EnglishText>"
    # SUZERAIN MENU TEXT: intentionally NONE. Pre-decouple "Route A" overrode each type's Shareable city-state
    # bonus DESCRIPTION (CITY_STATE_<TYPE>_BONUS_<Age>_7_DESCRIPTION) to advertise our per-pop add-on on the draft
    # menu. GEN-2 DECOUPLE (2026-07-13) removed that: the yields key off HOLDING the suzerainty, not which bonus
    # you draft, so annotating one option would mislead. Base bonus descriptions stay vanilla; the civic SUZERAIN
    # note + the dashboard Protectorates panel carry the explanation. No <LocalizedText> override is emitted here.
    # (If Route A is ever revived, it MUST use <LocalizedText><Replace Tag=... Language="en_US"> upsert - NOT
    #  <EnglishText><Row>, which duplicates the base tag -> load error -> CRASH; learned 2026-06-20.)
    $tl += '</Database>'
    $modRoot = Split-Path $root -Parent
    $ntDir = Join-Path $modRoot 'text\en_us'
    if (-not (Test-Path $ntDir)) { New-Item -ItemType Directory -Force -Path $ntDir | Out-Null }
    $ntFile = Join-Path $ntDir 'MetropolisAscendantNotes.generated.xml'
    Set-Content -LiteralPath $ntFile -Value (($tl -join $NL)) -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $ntFile -Raw) | Out-Null
    Write-Host "notes: valid | $noteRowCount per-age note strings -> $ntFile"

    # ---- GENERATED player-facing BONUS LIST (BBCode for Steam + Markdown for GitHub) ----
    # Mirrors the in-game node notes (same $noteText), grouped by Age -> node, so it can never drift from
    # what players see in-game. The game's [icon:...] UI tags don't render on Steam/GitHub, so they're
    # converted to words here. Node ids are turned into readable names.
    $iconWord = @{ 'YIELD_SCIENCE'='Science'; 'YIELD_CULTURE'='Culture'; 'YIELD_GOLD'='Gold';
                   'YIELD_PRODUCTION'='Production'; 'YIELD_FOOD'='Food'; 'YIELD_HAPPINESS'='Happiness';
                   'YIELD_DIPLOMACY'='Influence'; 'YIELD_POPULATION'='Population' }
    function Format-Note($t) {
        # Notes are authored "[icon:YIELD_X] Word", so simply dropping the glyph leaves the readable word.
        # Two exceptions get expanded to words first: Population (followed by "Urban Pop"/"Pop", not its own
        # word) and the Suzerain yield list (glyphs separated by "/" with no words at all). Everything else
        # is just removed.
        $t = $t -replace '\[icon:YIELD_POPULATION\]\s*Urban Pop','Urban Population' `
                -replace '\[icon:YIELD_POPULATION\]\s*Pop\b','Population'
        foreach ($k in $iconWord.Keys) {
            $t = $t -replace "\[icon:$k\]/", ($iconWord[$k] + '/') -replace "\[icon:$k\]\)", ($iconWord[$k] + ')')
        }
        $t = $t -replace '\[icon:YIELD_\w+\]\s*',''
        ($t -replace '\s+',' ').Trim()
    }
    $nodeOverride = @{ 'ORG_MILITARY'='Organized Military'; 'CODE_OF_LAWS'='Code of Laws'; 'DIPLOMATIC_SERVICE'='Diplomatic Service' }
    function Get-NodeName($id) {
        $kind = if ($id -match 'NODE_TECH') { 'Tech' } elseif ($id -match 'NODE_CIVIC') { 'Civic' } else { '' }
        $n = $id -replace '^NODE_(TECH|CIVIC)_(AQ|EX|MO)_','' -replace '^(MAIN_|BRANCH_)',''
        $disp = if ($nodeOverride.ContainsKey($n)) { $nodeOverride[$n] }
                else { (($n -split '_' | Where-Object { $_ } | ForEach-Object { $_.Substring(0,1).ToUpper() + $_.Substring(1).ToLower() }) -join ' ') }
        @{ Name=$disp; Kind=$kind }
    }
    $intro = "Every Metropolis Ascendant bonus, grouped by source. The Ascendancy civic-tree entries below are the exact text shown on each node's in-game panel, so this list can't drift from what you see in-game. Bonuses pay out across all your Settlements while your footprint stays within your earned allowance - you start with one Settlement and earn Charters to widen it, up to four - and switch off if you exceed it."
    $bb = @('[h1]Metropolis Ascendant - Full Bonus List[/h1]', "[i]Auto-generated from the mod's data, so it matches the in-game node notes exactly.[/i]", $intro)
    $md = @('# Metropolis Ascendant - Full Bonus List','',"*Auto-generated from the mod's data, so it matches the in-game node notes exactly.*",'',$intro)
    # The Gen-2 Ascendancy sections (tree nodes with their in-game text + boosts, feats, charters,
    # cards, pantheons) are injected between these markers by tools/gen-ascendancy.ps1 - run it AFTER
    # this script (publish.ps1 runs them in that order). Same marker-block mechanism as the README
    # tiers table. If you run only this script, the region stays empty until gen-ascendancy.ps1 runs.
    $bb += @('', '<!-- GEN:ascendancy -->', '<!-- /GEN:ascendancy -->')
    $md += @('', '<!-- GEN:ascendancy -->', '<!-- /GEN:ascendancy -->')
    # WONDERS & ARCADIA - not node-gated (so not in the per-age node loop above); described here as its own lane.
    $arcIntro = "Concentrate your Wonders and natural beauty into one city - an edge a sprawling AI empire can't match, because it spreads them thin across dozens of settlements."
    $arcLines = @(
      "Wonders enrich the city: each Building next to a Wonder gains +1 Happiness, and your Wonders raise the Appeal of the surrounding land. (Active while tall.)",
      "Discover a Natural Wonder to awaken Arcadia - an exploration unlock, not a tech. Then, while tall:",
      "Breathtaking rural tiles each gain +1 / +2 / +3 (by Age) Culture, Production, Happiness, Science and Food.",
      "Every Building and Wonder gains +1 / +2 / +3 (by Age) Culture and Gold for each adjacent Mountain.",
      "Mountains become workable - terrace a peak and it yields the full +1 / +2 / +3 Arcadia set (Culture, Production, Happiness, Science, Food). In Exploration and Modern a Breathtaking peak stacks both the rural and mountain bonuses.",
      "Water becomes bounty - every worked water tile yields by type (Navigable Rivers, Minor Rivers, Lakes, the open sea, Reefs and water Natural Wonders each give their own mix of Food, Gold, Science, Culture or Happiness, more in later Ages), and Buildings near Coast or a Navigable River gain Gold / Production. In Exploration you may work the open ocean, and a coastal city gains a flat Food / Production floor just for being on the sea - so a tile-starved island metropolis can still thrive."
    )
    $bb += @('', '[h2]Wonders & Arcadia[/h2]', $arcIntro, '[list]')
    foreach ($l in $arcLines) { $bb += "[*]$l" }
    $bb += '[/list]'
    $md += @('', '## Wonders & Arcadia', '', "*$arcIntro*", '')
    foreach ($l in $arcLines) { $md += "- $l" }
    $foundation = "Always on, no research needed: bonus Happiness and reduced specialist upkeep that grow with your city, plus +$suzPrimer Influence per turn to help you win your first city-states."
    $bb += @('', '[h2]Foundations[/h2]', $foundation)
    $md += @('', '## Foundations', '', $foundation)
    # SURVEYOR (issue #12) - a buildable unit, not node-gated, so described here.
    $surveyor = "A small footprint shouldn't cost you resources. Build a Surveyor in any Age to claim a resource tile up to 5 tiles from your Settlements into your metropolis - spent after a single claim, so one dense city can command resources a wide empire would spread across many. The resource keeps its normal yields; the power is the reach itself."
    $bb += @('', '[h2]Tall Resource Reach - the Surveyor[/h2]', $surveyor)
    $md += @('', '## Tall Resource Reach - the Surveyor', '', $surveyor)
    # RAZING (issue #3) - player-wide, not node-gated, so described here. Numbers pull from the live config so they never drift.
    $razeIntro = "A single dominant city can't keep the settlements it conquers, so razing becomes a real tool - tied to the tall playstyle, so a sprawling conquer-and-keep empire gains none of it."
    $razeLines = @(
      "Take a city by force: a one-time burst of +$razeCaptureGold / +$($razeCaptureGold*2) / +$($razeCaptureGold*3) (by Age) Gold and +$razeCaptureInf / +$($razeCaptureInf*2) / +$($razeCaptureInf*3) Influence the moment you capture it.",
      "Sack before you burn: your units earn +$razePillageFlat Gold and +$razePillageFlat Science on top of the base plunder for each building they pillage - a large city is worth far more to sack than a small town.",
      "Razing is near-instant - a city you can't hold is gone in a turn or two. While it burns it counts as a second settlement, so your tall bonuses briefly pause until it's razed (a short-term price for erasing a rival). Razing still turns other leaders against you."
    )
    $bb += @('', "[h2]Raze What You Can't Hold[/h2]", $razeIntro, '[list]')
    foreach ($l in $razeLines) { $bb += "[*]$l" }
    $bb += '[/list]'
    $md += @('', "## Raze What You Can't Hold", '', "*$razeIntro*", '')
    foreach ($l in $razeLines) { $md += "- $l" }
    $bbFile = Join-Path $modRoot 'docs\bonus-list.bbcode.txt'
    $mdFile = Join-Path $modRoot 'docs\bonus-list.md'
    Set-Content -LiteralPath $bbFile -Value (($bb -join $NL)) -NoNewline -Encoding UTF8
    Set-Content -LiteralPath $mdFile -Value (($md -join $NL)) -NoNewline -Encoding UTF8
    Write-Host "bonus list: $($bb.Count) BBCode lines -> $bbFile ; $mdFile"

    # ---- GENERATED BONUS -> TREE-DEPTH MAP (where each bonus gates + how deep in its tree) ----
    # Cross-references the $ages bonus->node config with the civ7-modding skill's progression-trees.md
    # (node Col = longest prereq-chain depth = "how early"; col 1 = root). Flags bonuses at Col >= 4 = late.
    $repoRoot = Split-Path (Split-Path $modRoot -Parent) -Parent   # ...\mods\metropolis-ascendant -> repo root
    $ptFile = Join-Path $repoRoot '.claude\skills\civ7-modding\references\progression-trees.md'
    if (Test-Path $ptFile) {
        $nodeCol=@{}; $nodeTree=@{}; $treeFreeRoot=@{}; $curTree=''
        foreach ($line in (Get-Content -LiteralPath $ptFile)) {
            if ($line -match '^###\s+(TREE_\S+)') { $curTree=$matches[1]; continue }
            if ($line -match '^\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*`(NODE_[A-Z0-9_]+)`') {
                $c=[int]$matches[1]; $cost=[int]$matches[2]; $n=$matches[3]
                $nodeCol[$n]=$c; $nodeTree[$n]=$curTree
                if ($c -le 1 -and $cost -le 10) { $treeFreeRoot[$curTree]=$true }   # FREE ROOT (e.g. AQ Agriculture, cost 1 = turn-1 freebie) -> don't count as a depth layer
            }
        }
        # Effective depth = raw column minus 1 when the node's tree has a free turn-1 root (so AQ tech depths drop by 1).
        function Get-Depth($node) {
            if (-not $nodeCol.ContainsKey($node)) { return @{ Col=99; Disc=$false } }
            $disc = ($treeFreeRoot[$nodeTree[$node]] -eq $true)
            $col = if ($disc) { [Math]::Max(1, $nodeCol[$node]-1) } else { $nodeCol[$node] }
            @{ Col=$col; Disc=$disc }
        }
        $depthLabels = [ordered]@{
            Spine        = 'Specialist worker cap (T1-T3)'
            Economic     = 'Specialist slots + Resource cap (T1-T2)'
            EconomicDeep = 'Resource cap (T3)'
            Science      = 'Science adjacency (T1-T3) + Great Work slots'
            ScienceDeep  = 'Science per Urban Pop (T3)'
            Culture      = 'Culture adjacency (T1-T3)'
            CultureDeep  = 'Culture per Urban Pop (T3)'
            Wonders      = 'Wonder Production %'
            Commerce     = 'Trade Routes + range + resource Happiness'
            Military     = 'Production per Urban Pop (T3)'
            MilitaryDeep = 'Combat Strength (all combat)'
            FoodCap      = 'Under-cap Food + rural Food warehouse'
            ProdCap      = 'Under-cap Production + rural Prod warehouse'
            Religion     = 'Temple GW slots + Happiness/building + Culture per Great Work'
            Diplomatic   = 'Suzerain note marker (per-pop yields gate on the drafted CS bonus, not this node)'
        }
        $dm = @('# Metropolis Ascendant - Bonus -> Tree-Depth Map','',
                '*Generated by tools/gen-ascendant.ps1 - cross-references the $ages bonus->node config with the',
                'civ7-modding skill''s progression-trees.md. **Depth** = how many real research/civic steps until the',
                'bonus comes online (longest prereq-chain depth, with any FREE turn-1 tree root discounted - see †).',
                'Rows at **Depth >= 4 are flagged late**. `+M` = the bonus sits on the node''s depth-2 MASTERY (later still).',
                '',
                '† = Agriculture-discounted: the Antiquity tech tree''s root (Agriculture, cost 1, researched turn 1) is',
                'not counted as a layer, so AQ tech depths shown = raw column - 1. (No other tree has a free root, so',
                'only AQ techs are discounted.)*')
        foreach ($a in ($ages | Where-Object { $_.FanOut })) {
            $rows = @()
            foreach ($k in $depthLabels.Keys) {
                if (-not $a.Nodes.ContainsKey($k)) { continue }
                $d = Get-Depth $a.Nodes[$k]
                $rows += [pscustomobject]@{ Bonus=$depthLabels[$k]; Node=$a.Nodes[$k]; Col=$d.Col; Disc=$d.Disc; Mast=$false }
            }
            if ($a.Nodes.ContainsKey('Wonders')) {
                $d = Get-Depth $a.Nodes.Wonders
                $rows += [pscustomobject]@{ Bonus='Resort (appeal + Natural-Wonder yields)'; Node=$a.Nodes.Wonders; Col=$d.Col; Disc=$d.Disc; Mast=$true }
            }
            if ($a.HubNode)  { $d=Get-Depth $a.HubNode;  $rows += [pscustomobject]@{ Bonus='Hub influence (+Influence on diplomacy building)'; Node=$a.HubNode; Col=$d.Col; Disc=$d.Disc; Mast=$false } }
            if ($a.FortNode) { $d=Get-Depth $a.FortNode; $rows += [pscustomobject]@{ Bonus='Fort Town (district HP + heal + gold)'; Node=$a.FortNode; Col=$d.Col; Disc=$d.Disc; Mast=$false } }

            $dm += @('', "## $($a.AgeName)", '', '| Depth | Bonus | Node | Tree |', '|----:|-------|------|------|')
            foreach ($r in ($rows | Sort-Object @{e={if($_.Mast){$_.Col+0.5}else{$_.Col}}}, Bonus)) {
                $nm = Get-NodeName $r.Node
                $colShow = if ($r.Col -eq 99) { '?' } else { [string]$r.Col }
                if ($r.Mast) { $colShow = "$colShow+M" }
                if ($r.Disc) { $colShow = "$colShow†" }
                $flag = if ($r.Col -ge 4 -and $r.Col -ne 99) { ' :warning:' } else { '' }
                $dm += "| $colShow$flag | $($r.Bonus) | $($nm.Name) | $($nm.Kind) |"
            }
            $late = $rows | Where-Object { $_.Col -ge 4 -and $_.Col -ne 99 } | Sort-Object Col
            if ($late) {
                $dm += @('', "**Comes alive late (effective depth >= 4) in $($a.AgeName):**")
                foreach ($r in $late) { $nm = Get-NodeName $r.Node; $m = if($r.Mast){' (+ node mastery)'}else{''}; $dm += "- **Depth $($r.Col)$m** - $($r.Bonus) on $($nm.Name) ($($nm.Kind))" }
            }
        }
        $dm += @('', '## Not tree-gated (for completeness)',
                 '- **Safety nets** (bonus Happiness, -50% specialist upkeep) + the **age-transition reseed** are ungated/always-on (reseed bridges from age turn 1 until the host node is researched).',
                 '- **Suzerain per-pop yields** gate on drafting each city-state type''s repeatable bonus (REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS), NOT on a tree node - the Diplomatic row above only marks where the SUZERAIN note sits.')
        $dmFile = Join-Path $modRoot 'docs\TREE-DEPTH-MAP.md'
        Set-Content -LiteralPath $dmFile -Value (($dm -join $NL)) -NoNewline -Encoding UTF8
        Write-Host "tree-depth map: -> $dmFile"
    } else {
        Write-Host "tree-depth map: SKIPPED (progression-trees.md not found at $ptFile)"
    }
}
# ---- SYNC hand-authored docs (growth-milestone numbers + tested-on version are single-sourced) ----
# TIERS RETIRED 2026-07-19 (Chris): Gen-2 moved all T2/T3 content onto the Ascendancy tree; the only
# survivors of the old ladder are the FIRST threshold's two features (+Happiness grant, specialist
# upkeep relief until Ecstatic). Docs describe those as "the growth milestone" — no tier language.
# Keeps the player-facing numbers in lockstep with $ages / $testedVersion: the modinfo <Description>
# milestone sentence + version, and the mod README's milestone sentence + version. Prose stays
# hand-authored; only these are rewritten, so retuning Pops/Happiness can never leave a stale doc.
$mileSentence = "GROWTH MILESTONE — at $($ages[0].Pops[0]) Urban Population in $($ages[0].AgeName), $($ages[1].Pops[0]) in $($ages[1].AgeName), $($ages[2].Pops[0]) in $($ages[2].AgeName): your metropolis gains +$($ages[0].Happiness)/+$($ages[1].Happiness)/+$($ages[2].Happiness) Happiness (by Age), and its Specialists cost 50% less Food and Happiness upkeep until the city reaches Ecstatic."
$miFile = Join-Path $modDir "$modName.modinfo"
if (Test-Path $miFile) {
    $mt = Get-Content -LiteralPath $miFile -Raw
    $mt = $mt -replace 'GROWTH MILESTONE — .*?Ecstatic\.', $mileSentence
    $mt = $mt -replace 'Built and tested on Civilization VII [0-9]+(?:\.[0-9]+)*\.?', "Built and tested on Civilization VII $testedVersion."
    Set-Content -LiteralPath $miFile -Value $mt -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $miFile -Raw) | Out-Null   # re-validate after the edit
    Write-Host "synced modinfo: growth-milestone numbers + tested-on version ($testedVersion)"
}
$rmFile = Join-Path $modDir 'README.md'
if (Test-Path $rmFile) {
    $tbl = "<!-- GEN:tiers (auto-generated by gen-ascendant.ps1) -->$($NL)At **$($ages[0].Pops[0]) Urban Population** in $($ages[0].AgeName) (**$($ages[1].Pops[0])** in $($ages[1].AgeName), **$($ages[2].Pops[0])** in $($ages[2].AgeName)), your metropolis gains **+$($ages[0].Happiness)/+$($ages[1].Happiness)/+$($ages[2].Happiness) Happiness** (by Age), and its Specialists cost **50% less Food and Happiness upkeep** until the city reaches **Ecstatic**.$($NL)<!-- /GEN:tiers -->"
    $rt = Get-Content -LiteralPath $rmFile -Raw
    $rt = $rt -replace '(?s)<!-- GEN:tiers.*?<!-- /GEN:tiers -->', $tbl
    $rt = $rt -replace 'Civilization VII \*\*[0-9][0-9.]*\*\*', "Civilization VII **$testedVersion**"
    Set-Content -LiteralPath $rmFile -Value $rt -NoNewline -Encoding UTF8
    Write-Host "synced README: growth-milestone sentence + tested-on version"
}

Write-Host "DONE"
