# =====================================================================================
# Tall Metropolis - unified modifiers generator (per-hemisphere model, item K, 2026-06-18)
# =====================================================================================
# Emits each age's data/<age>/modifiers.xml IN FULL from the $ages config table below -
# deterministic, self-validating (parses the result as XML), and easy to retune. Supersedes
# the old gen-adjacency-modifiers.ps1 (which only managed the adjacency block); this script
# owns the WHOLE file: marker + homeland core + distant-lands core + adjacency + ATTACH_ALL.
#
# PER-HEMISPHERE MODEL: anti-wide falloff is scoped per hemisphere (Civ VII's Homeland vs
# Distant Lands binary) with a steeper GEOMETRIC curve on the SCALABLE rewards:
#   SOLO    = 1 settlement in the hemisphere -> full   (wonder 100%, per-pop Divisor 2, adj Divisor 1)
#   COMPACT = exactly 2 settlements          -> half   (50%, Divisor 4, adj Divisor 2)
#   QUARTER = exactly 3 settlements          -> quarter(25%, Divisor 8, adj Divisor 4)
#   off at 4+ settlements in that hemisphere.
# Bands are threshold + inverse-threshold pairs (NOT RequiresExactCount): the base game only
# proves OnlyHomelands/OnlyDistantlands counting with a plain RequiredCount threshold (EX
# Expansionist legacy), so exact-count + a hemisphere filter is unproven and risks silently
# never firing.
#
# Hemisphere scoping:
#   - Antiquity (Distant=$false): NO Distant Lands exist - emits ONE unscoped set (no
#     REQUIREMENT_CITY_IS_DISTANT_LANDS, no OnlyHomelands arg, plain total settlement count).
#     Preserves AQ's already-playtested behaviour; only the geometric QUARTER band is new.
#   - Exploration / Modern (Distant=$true): emit a HOMELAND set (city req
#     REQUIREMENT_CITY_IS_DISTANT_LANDS inverse + settlement arg OnlyHomelands=true) AND a
#     DISTANT-LANDS set (_DL ids; city req REQUIREMENT_CITY_IS_DISTANT_LANDS + settlement arg
#     OnlyDistantlands=true). NB the base-game spelling "OnlyDistantlands" (lowercase L) -
#     the capitalised form silently never fires.
#
# What does NOT get a distant clone (homeland set only):
#   - GREAT_WORKS: targets BUILDING_PALACE via COLLECTION_PLAYER_CAPITAL_CITY (the capital is
#     in the homeland); integer slots, so kept BINARY on/off at 4 settlements (no geometric).
#   - COLLECTION_SLOTS: COLLECTION_PLAYER_CONSTRUCTIBLES can take NO settlement/city requirement
#     (hard-crashes at load, bisected 2026-06-14), so it can't be hemisphere-scoped; it stays
#     tech-gated only and applies to every slotted building the player owns (both hemispheres).
#
# Specialist CAP + safety nets stay CLEAN on/off and count CITIES ONLY (OnlyCities=true), as a
# safety valve: a town can never revoke a cap slot and strand placed specialists into the
# over-cap unhappiness death-spiral. Rewards count ALL settlements (towns included).
#
# Gate: every REWARD + cap carries an OwnerRequirements gate on the host TECH NODE
# (REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE + MinDepth=1 - the MinDepth child is
# REQUIRED or it silently never fires). The 2 safety nets are intentionally UNGATED (always-on).
#
# RE-RUNNABLE + DETERMINISTIC: re-running with unchanged config reproduces the files byte-for-byte.
param([switch]$Test)   # -Test emits the throwaway metropolis-ascendant-test mod (low pop thresholds 2/4/6 + tech gate removed) for fast in-game validation
$ErrorActionPreference = 'Stop'
$TestMode = $Test.IsPresent

$adjRules = [ordered]@{
    'QuarterScience'      = 'QUARTER_SCIENCE'
    'QuarterCulture'      = 'QUARTER_CULTURE'
    'WonderScience'       = 'WONDER_SCIENCE'
    'WonderCulture'       = 'WONDER_CULTURE'
    'MountainCulture'     = 'MOUNTAIN_CULTURE'
    'ResourceScience'     = 'RESOURCE_SCIENCE'
    'NaturalWonderCulture'= 'NATURAL_WONDER_CULTURE'
}

# Per age: suffix, age/tech display names, host tech node, 3 tier population gates, flat Happiness
# safety amount, the 3 wonder-% band values (solo/compact/quarter), Palace GW slot amount, the
# per-slotted-building collection-slot amount, and whether Distant Lands exist (EX/MO yes).
# GW = Palace Great-Work slots; Collection = +ANY slot on every slotted building (both BUMPED 2026-06-19
# per playtest - a pop-40 science city couldn't store 3-4 Codices even maxed). ResCap = per-tier resource
# capacity grant (workstream J: more resources assignable -> +1 GDP each + yields). Trade = +trade routes
# (J: import resources -> +1 GDP each, fills the capacity). Economic-victory levers; GDP != gold income.
# FAN-OUT MODEL (Metropolis Ascendant): instead of every bonus gating on one host tech per age, each
# modifier family carries a DOMAIN gate node. `Nodes` maps domain -> tree node. In ANTIQUITY the domains
# are spread across real tech/civic nodes (the experiment); EXPLORATION/MODERN keep ALL domains on the old
# single host node (v3 behaviour) until the fan-out is ported there (ROADMAP Phase 4). Additive per node:
# each node lights its own slice. Domains: Spine=specialist worker-cap; Science/ScienceDeep; Culture;
# Economic; Military (new). `FanOut=$true` enables the new AQ-only families (military production per pop,
# Qajar-style early Food/Production, economic trade-route RANGE). The safety nets stay UNGATED (always-on).
$ages = @(
    @{ Key='antiquity';   Sfx='AQ'; AgeName='Antiquity';   Node='NODE_TECH_AQ_CURRENCY';    TechName='Currency'; BonusAge='ANTIQUITY';
       Pops=@(5,9,12);   Happiness=10; Wonders=@(20,10,5); GW=3; Collection=2; ResCap=@(2,2,2); Trade=2; Distant=$false;
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
         @{ Node='NODE_TECH_AQ_WHEEL';                Key='ECONOMIC2'}   # moved off Skilled Trades (col5) onto Wheel
         @{ Node='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS';   Key='TRADE'    }   # moved off Commerce (col6) onto Code of Laws (shares with Suzerain note)
         @{ Node='NODE_TECH_AQ_BRONZE_WORKING';       Key='MILITARY' }
         @{ Node='NODE_CIVIC_AQ_MAIN_ORG_MILITARY';   Key='MILITARY2'}
         @{ Node='NODE_TECH_AQ_MILITARY_TRAINING';    Key='FORT'     }
         @{ Node='NODE_TECH_AQ_IRRIGATION';           Key='FOODCAP'  }
         @{ Node='NODE_TECH_AQ_BRONZE_WORKING';       Key='PRODCAP'  }   # moved off Engineering (col5) onto Bronze Working (shares with Military prod)
         @{ Node='NODE_CIVIC_AQ_MAIN_CODE_OF_LAWS';   Key='SUZERAIN' } ) }
    @{ Key='exploration'; Sfx='EX'; AgeName='Exploration'; Node='NODE_TECH_EX_EDUCATION';   TechName='Education'; BonusAge='EXPLORATION';
       Pops=@(8,14,20);  Happiness=12; Wonders=@(25,13,6); GW=3; Collection=2; ResCap=@(2,2,2); Trade=2; Distant=$true;
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
       Pops=@(10,16,24); Happiness=15; Wonders=@(30,15,8); GW=4; Collection=3; ResCap=@(3,3,3); Trade=3; Distant=$true;
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
$testedVersion = '1.4.1'

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
$suzPerPopDiv = 3  # per-pop divisor for suzerain yields: +1 yield per 3 Urban Pop (stacks on the node per-pop).
                   # NB the unlock is BOOLEAN (drafting the type's Shareable bonus flips it on; a 2nd CS of that
                   # type doesn't stack - no per-pop-per-count effect exists), so magnitude lives in this divisor.
                   # Push to 2 for "doubles your per-pop in that domain"; raise back toward 5 if late-game too hot.
$suzDiploAmt  = 2  # +Influence (YIELD_DIPLOMACY) per TOTAL suzerain, player-level (gated on the Diplomatic Shareable bonus)
$suzPopAmt    = 1  # free capital Population per Expansionist CS (signature; gated on the Expansionist Shareable bonus)
$suzPrimer    = 3  # flat Influence/turn (per Palace) to bootstrap winning the first city-states (ungated)
$hubInfluenceAmt = 3  # town-spec "Hub Town" bucket internalized: flat +Influence ON the age's Diplomacy building
                      # (proven EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD, NOT per-pop - influence is player-level),
                      # gated behind that building's unlock node. The influence FLOOR the suzerain layer compounds.
                      # Raise for more influence; the Deity playtest showed influence (+5 total) was the binding cap.
$fortHealth = 25      # town-spec "Fort Town" bucket: +HP to all the player's Districts (toughens the tall city
$fortHeal   = 5       # against a numerically superior attacker) + heal/turn to the player's Units. Base Fort values.
$fortGold   = 1       # +Gold on Fortified districts (the Fort Town gold-on-fortifications benefit).
$religiousHappy = 2   # "Religious Site" Temple bucket: +Happiness on every Building (base value).
$resortAppeal   = 1   # "Resort" bucket: +Gold & +Happiness on Appealing tiles.
$resortNWPercent= 50  # "Resort" bucket: +% all yields on Natural-Wonder tiles (self-targets - only pays near a NW).
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
$warehouse = @{
    AQ = @{ Food='AQTownPastureFood, AQTownPlantationFood, AQTownDesertFloodplainFeatureFood, AQTownGrasslandFloodplainFeatureFood, AQTownPlainsFloodplainFeatureFood, AQTownTropicalFloodplainFeatureFood, AQTownTundraFloodplainFeatureFood, AQTownFlatTerrainFood, AQTownFishingBoatResourceFood, AQTownAtollFeatureFood, AQTownLotusFeatureFood, AQTownReefFeatureFood, AQTownColdReefFeatureFood, AQTownCoastTerrainFood, AQTownNavigableRiverFood';
            Prod='AQTownClayPitResourceProduction, AQTownClayPitProduction, AQTownMineResourceProduction, AQTownQuarryProduction, AQTownRoughTerrainProduction, AQTownWoodcutterResourceProduction, AQTownCampProduction, AQTownVegetatedFeatureProduction';
            Happy='AQHappinessProjectResourceHappiness' }
    EX = @{ Food='EXTownPastureFood, EXTownPlantationFood, EXTownDesertFloodplainFeatureFood, EXTownGrasslandFloodplainFeatureFood, EXTownPlainsFloodplainFeatureFood, EXTownTropicalFloodplainFeatureFood, EXTownTundraFloodplainFeatureFood, EXTownFlatTerrainFood, EXTownFishingBoatResourceFood, EXTownAtollFeatureFood, EXTownLotusFeatureFood, EXTownReefFeatureFood, EXTownColdReefFeatureFood, EXTownCoastTerrainFood, EXTownNavigableRiverFood';
            Prod='EXTownClayPitResourceProduction, EXTownClayPitProduction, EXTownMineResourceProduction, EXTownQuarryProduction, EXTownRoughTerrainProduction, EXTownWoodcutterResourceProduction, EXTownCampProduction, EXTownVegetatedFeatureProduction';
            Happy='EXHappinessProjectResourceHappiness' }
    MO = @{ Food='MOTownPastureFood, MOTownPlantationFood, MOTownDesertFloodplainFeatureFood, MOTownGrasslandFloodplainFeatureFood, MOTownPlainsFloodplainFeatureFood, MOTownTropicalFloodplainFeatureFood, MOTownTundraFloodplainFeatureFood, MOTownFlatTerrainFood, MOTownFishingBoatResourceFood, MOTownAtollFeatureFood, MOTownLotusFeatureFood, MOTownReefFeatureFood, MOTownColdReefFeatureFood, MOTownCoastTerrainFood, MOTownNavigableRiverFood';
            Prod='MOTownClayPitResourceProduction, MOTownClayPitProduction, MOTownMineResourceProduction, MOTownOilRigResourceProduction, MOTownQuarryProduction, MOTownRoughTerrainProduction, MOTownWoodcutterResourceProduction, MOTownCampProduction, MOTownVegetatedFeatureProduction, MOTownWetFeatureProduction';
            Happy='MOHappinessProjectResourceHappiness' }
}

# HARD CUTOFF (2026-06-21): the per-hemisphere REWARD scaling is now BINARY, not geometric. Full bonus
# at exactly 1 settlement in the hemisphere (the SOLO band), NOTHING at 2+. The mod's true intent is a strict
# 1-Homeland + 1-Distant-Lands empire, so the old COMPACT (2-3 settlements -> half) / QUARTER (3-4 -> quarter)
# taper is REMOVED: $bandList holds only SOLO, so the wonder / per-pop / adjacency / military loops emit one
# (full) modifier each, gated on "fewer than 2 settlements in this hemisphere" (SOLO = Settle 2 inverse).
# NB the SPECIALIST CAP + safety nets are deliberately NOT hard-cut: they keep their lenient non-revoking
# anti-wide gate (off only at 4+ Cities / 5+) so slipping to a 2nd settlement turns off the YIELD rewards but
# never REVOKES a placed-specialist cap slot (which would trigger the over-cap unhappiness death-spiral). The
# magnitudes below are the former "full" SOLO values; RE-TUNE here after a Deity 1+1 playtest if tall can't keep pace.
$perPopDiv = @{ SOLO=2 }   # per-population reward divisor (full). +1 yield per 2 Urban Pop.
$adjDiv    = @{ SOLO=1 }   # adjacency-flat divisor (full). +1 adjacency per tier (max +3 across the 3 tiers).
$bandList  = @('SOLO')     # HARD CUTOFF: single band = 1 settlement/hemisphere. (Add 'COMPACT','QUARTER' back to restore the taper.)
# IDEAS 1 & 2 (2026-06-23): align with the 1.4.1 STAGED-HAPPINESS model (per-Age thresholds Joyous 20/40/60,
# Ecstatic 40/80/120 for AQ/EX/MO). Mechanic confirmed in 1.4.1 data: REQUIREMENT_SETTLEMENT_HAPPINESS_STAGE_MATCHES
# (Args HappinessStage + IsGreaterThanOrEquals); inverse="true" on it = "below that stage".
# IDEA 1 - happiness-stage PAYOFF lane: a metropolis that runs happy earns EXTRA per-pop yield (the lanes tall holds).
$stageYields      = @('YIELD_SCIENCE','YIELD_CULTURE')  # which yields the stage lane pays
$stageJoyousDiv   = 4   # at >= JOYOUS:   +1 of each stage-yield per 4 Urban Pop
$stageEcstaticDiv = 4   # at >= ECSTATIC: ANOTHER +1 of each per 4 Urban Pop (stacks on Joyous -> ~+1 per 2 at Ecstatic). FIRST-PASS values; retune after a playtest.
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
# which DOMAIN each Science/Culture adjacency rule belongs to (gates it on that domain's node)
$ruleDomain = @{ QuarterScience='Science'; WonderScience='Science'; ResourceScience='Science';
                 QuarterCulture='Culture'; WonderCulture='Culture'; MountainCulture='Culture'; NaturalWonderCulture='Culture' }

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
# geometric band gate for an all-settlements reward (OnlyCities=false)
function BandGate($band, $hemiArg) {
    switch ($band) {
        'SOLO'    { @(Settle 2 $true  'false' $hemiArg) }
        'COMPACT' { @((Settle 2 $false 'false' $hemiArg), (Settle 3 $true 'false' $hemiArg)) }
        'QUARTER' { @((Settle 3 $false 'false' $hemiArg), (Settle 4 $true 'false' $hemiArg)) }
    }
}

# ---- modifier builders (each returns a full <Modifier>..</Modifier> at 1-tab indent) ----
function M-WorkerCap($sfx,$tier,$node,$pop,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $desc = if ($tier -eq 1) { "$NL`t`t<String context=`"Description`">LOC_MA_TIER1_DESCRIPTION</String>" } else { '' }
    "`t<Modifier id=`"MA_${sfx}_T${tier}_WORKER_CAP${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_WORKER_CAP`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(Settle 4 $true 'true' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">1</Argument>$desc$NL`t</Modifier>"
}
function M-Upkeep($sfx,$pop,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    "`t<Modifier id=`"MA_${sfx}_T1_SPECIALIST_UPKEEP${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_WORKER_MAINTENANCE_EFFICIENCY`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(StageReq $upkeepReliefMaxStage $true)$(Settle 5 $true 'true' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_FOOD, YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Percent`">50</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_SAFETY_DESCRIPTION</Argument>$NL`t</Modifier>"
}
function M-Happiness($sfx,$pop,$amt,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    "`t<Modifier id=`"MA_${sfx}_T1_HAPPINESS${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(Settle 5 $true 'true' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# IDEA 1 (2026-06-23): happiness-stage PAYOFF lane. Per-pop yield gated on the city being at/above a happiness
# stage (Joyous, then Ecstatic). NODE-GATED on the domain node (Science half -> Science node, Culture half ->
# Culture node, same as the T3 per-pop bonuses) so it's ADVERTISED on the tree (STAGE_SCIENCE/STAGE_CULTURE notes);
# also SOLO-gated like the per-pop rewards (full only at 1 settlement/hemisphere) and hemisphere-scoped.
# The Joyous and Ecstatic modifiers STACK (an Ecstatic city is also >= Joyous), so Ecstatic = Joyous + extra.
function M-StagePayoff($sfx,$node,$pop,$stage,$yield,$div,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate 'SOLO' $h) -join $NL
    $yname = ($yield -replace '^YIELD_','')
    $sname = ($stage -replace '^HAPPINESS_STAGE_','')
    "`t<Modifier id=`"MA_${sfx}_STAGE_${sname}_${yname}${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_POPULATION`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$(StageReq $stage $false)$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Urban`">true</Argument><Argument name=`"Rural`">false</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_STAGE_DESCRIPTION</Argument>$NL`t</Modifier>"
}
function M-Wonders($sfx,$node,$pop,$band,$pct,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate $band $h) -join $NL
    "`t<Modifier id=`"MA_${sfx}_T2_WONDERS_${band}${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_WONDER_PRODUCTION`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Percent`">$pct</Argument>$NL`t</Modifier>"
}
function M-GreatWorks($sfx,$node,$pop,$amt,$hemi) {
    # homeland set only; binary on/off; capital is homeland so scope the count by OnlyHomelands.
    $h = HemiArg $hemi
    "`t<Modifier id=`"MA_${sfx}_T2_GREAT_WORKS`" collection=`"COLLECTION_PLAYER_CAPITAL_CITY`" effect=`"EFFECT_CITY_ADJUST_GREAT_WORK_SLOTS`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL$(PopReq $pop)$(Settle 2 $true 'false' $h)$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"ConstructibleType`">BUILDING_PALACE</Argument>$NL`t`t<Argument name=`"SlotType`">GREATWORKSLOT_ANY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
function M-CollectionSlots($sfx,$node,$amt) {
    # CRASH FIX: COLLECTION_PLAYER_CONSTRUCTIBLES must carry NO settlement/city requirement (hard
    # crash at load), so this stays tech-gated only and is NOT hemisphere-scoped.
    "`t<Modifier id=`"MA_${sfx}_T3_COLLECTION_SLOTS`" collection=`"COLLECTION_PLAYER_CONSTRUCTIBLES`" effect=`"EFFECT_CONSTRUCTIBLE_ADJUST_GREAT_WORK_SLOTS`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CONSTRUCTIBLE_HAS_GREAT_WORK_SLOT`"/>$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"SlotType`">GREATWORKSLOT_ANY</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_SLOTS_DESCRIPTION</Argument>$NL`t</Modifier>"
}
function M-PerPop($sfx,$node,$pop,$band,$yield,$div,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate $band $h) -join $NL
    $yname = ($yield -replace '^YIELD_','')
    "`t<Modifier id=`"MA_${sfx}_T3_${yname}_${band}${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_POPULATION`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Urban`">true</Argument><Argument name=`"Rural`">false</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_TIER3_DESCRIPTION</Argument>$NL`t</Modifier>"
}
function M-Adjacency($sfx,$tier,$node,$pop,$rule,$band,$div,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate $band $h) -join $NL
    $frag = $adjRules[$rule]
    "`t<Modifier id=`"MA_${sfx}_T${tier}_ADJ_${frag}_${band}${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_ADJACENCY_FLAT_AMOUNT`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Adjacency_YieldChange`">$rule</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_TIER3_DESCRIPTION</Argument>$NL`t</Modifier>"
}
# workstream J: per-tier resource CAPACITY for the tall city (assign more resources -> +1 GDP each +
# yields). SOLO-gated (full only at 1 settlement in the hemisphere) since it's a potent integer grant;
# pop-tiered + tech-gated + hemisphere-scoped like the other city rewards. EFFECT_CITY_ADJUST_RESOURCE_CAP
# takes only Amount (base proof: Qing capital +2, Monopolies +1).
function M-ResourceCap($sfx,$tier,$node,$pop,$amt,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate 'SOLO' $h) -join $NL
    "`t<Modifier id=`"MA_${sfx}_T${tier}_RESOURCE_CAP${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_RESOURCE_CAP`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# workstream J: +trade-route capacity (import resources -> +1 GDP each, fills the resource capacity).
# Player-wide (COLLECTION_OWNER), so NOT hemisphere-scoped and NOT pop-tiered; tech-gated + anti-wide
# (off at 4+ TOTAL settlements - lenient so the 1-homeland+1-distant tall build keeps it). MajorsOnly
# mirrors the base EX economic trade-capacity card. EFFECT_PLAYER_ADJUST_TRADE_CAPACITY (Amount + MajorsOnly).
function M-TradeRoutes($sfx,$node,$amt) {
    "`t<Modifier id=`"MA_${sfx}_TRADE_ROUTES`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_TRADE_CAPACITY`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"MajorsOnly`">true</Argument>$NL`t</Modifier>"
}
# FAN-OUT (AQ): AUTHENTIC Qajar mechanic, now GATED + SPLIT per yield. Base effect = EFFECT_CITY_ADJUST_YIELD_
# PER_UNDER_SETTLEMENT_CAP on COLLECTION_PLAYER_CAPITAL_CITY (DLC\qajar\modules\data\civilizations-shared-
# gameeffects.xml uses ONE modifier with comma YieldType "YIELD_FOOD,YIELD_PRODUCTION"). It grants Amount x
# (settlement cap minus current settlements) of the yield in the capital - the further UNDER cap you are, the
# bigger; zero at/over cap (so it self-scopes; an AI near cap gets ~0). We SPLIT it into one modifier per
# yield so each can gate on its own thematic node: Food on Irrigation, Production on Engineering (tech-node
# gate in OwnerRequirements). The self-taper still handles "wide", so no extra anti-wide gate is needed.
# COLLECTION: COLLECTION_PLAYER_CITIES (NOT _CAPITAL_CITY). The under-cap MARGIN is player-wide, so every
# city computes the same per-under-cap amount; using all-cities means a DISTANT-LANDS city in EX/MO also gets
# it (the old capital-only collection left the distant city dry - the deferred distant-lands TODO). For a
# 1-city AQ build this is identical (capital == only city); a wide AI is at/over cap so each city still gets ~0.
function M-UnderCapYield($sfx,$yield,$amt,$node) {
    $yname = ($yield -replace '^YIELD_','')
    "`t<Modifier id=`"MA_${sfx}_UNDER_CAP_${yname}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_UNDER_SETTLEMENT_CAP`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t</Modifier>"
}
# FAN-OUT (AQ): economic-domain reachability helper. +trade-route RANGE (land + sea) so a tall one-city
# player can actually reach foreign markets / city-states to trade with and (later) suzerain. Gated on the
# Economic node, anti-wide off at 4+ total settlements. EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE (DomainType + Amount).
# NOTE (ROADMAP Phase 3): to tie this specifically to holding an ECONOMIC suzerain, gate on
# REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS referencing an economic city-state bonus once the suzerain layer lands.
function M-TradeRange($sfx,$node,$domainType,$amt) {
    $dn = ($domainType -replace '^DOMAIN_','')
    "`t<Modifier id=`"MA_${sfx}_TRADE_RANGE_${dn}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_TRADE_ROUTE_RANGE`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"DomainType`">$domainType</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# FAN-OUT (AQ) Military DEEPEN: flat +Strength in ALL combat (offense AND defense), scoped to the tall player.
# Effect/collection pattern from the base-game Scorched Earth tradition SCORCHED_EARTH_MOD_COMBAT_STRENGTH
# (COLLECTION_PLAYER_COMBAT + EFFECT_ADJUST_UNIT_STRENGTH_MODIFIER). Gated in OwnerRequirements on the
# military-deepen node + anti-wide (<4 total settlements) so AI doesn't get it.
# DESIGN (2026-06-20): deliberately ALWAYS-ON, no REQUIREMENT_PLAYER_IS_ATTACKING. A tall one-city
# player is usually outnumbered and on the defensive, so an attack-only bonus (which is what the copied
# Scorched Earth/Persia templates use) would do nothing in the fights that matter most; always-on still helps
# when pushing for an enemy capital (the breadth-scored military victory path).
# NOTE: must be COLLECTION_PLAYER_COMBAT, NOT COLLECTION_UNIT_COMBAT. The latter only resolves when the
# modifier is bound directly to a unit (ability/promotion). We deliver via the COLLECTION_MAJOR_PLAYERS
# attach wrapper, i.e. attached to the PLAYER, so the player-scoped combat collection is required - with
# COLLECTION_UNIT_COMBAT there is no unit context and the bonus silently never applies (verified in-game).
function M-CombatStrength($sfx,$node,$amt) {
    $reqs = @()
    if (-not $TestMode) { $reqs += "`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE`"><Argument name=`"ProgressionTreeNodeType`">$node</Argument><Argument name=`"MinDepth`">1</Argument></Requirement>" }
    $reqs += (Settle $tallCap $true 'false' '')
    $owner = "`t`t<OwnerRequirements>$NL$($reqs -join $NL)$NL`t`t</OwnerRequirements>$NL"
    "`t<Modifier id=`"MA_${sfx}_T3_COMBAT_STRENGTH`" collection=`"COLLECTION_PLAYER_COMBAT`" effect=`"EFFECT_ADJUST_UNIT_STRENGTH_MODIFIER`">$NL$owner`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<String context=`"Preview`">LOC_MA_COMBAT_STRENGTH_PREVIEW</String>$NL`t</Modifier>"
}
# AGE-TRANSITION RESEED (EX/MO only): bridges the early-age "valley". At the start of a new age EVERY gated
# bonus is dormant - you haven't researched the new age's nodes yet - while wide AIs already run N cities at
# base x N. That is the playtest cliff (Exploration turn 1: ~1/3 science, ~1/6 production vs the leader,
# right after leading science at end of Antiquity). This grants per-pop yield live FROM TURN 1, leaning on
# the POPULATION that carries across the transition (wide civs spread pop thin across many cities, so per-pop
# barely helps them; the <4-settlement anti-wide gate excludes them further). It switches OFF the moment you
# complete the age host node (when the real banded kit turns on) via an INVERSE node gate - a clean handoff,
# no permanent inflation, mutually exclusive with the kit so no double-dip. Magnitude = SOLO per-pop divisor,
# i.e. the same intensity the kit resumes at, so the bridge is seamless. Tune yields/divisor after playtest;
# Production is the obvious add (worst turn-1 gap) but risks snowballing infrastructure - Science+Culture
# (the lanes tall holds) first.
function M-Reseed($sfx,$hostNode,$pop,$yield,$div) {
    $yname = ($yield -replace '^YIELD_','')
    $owner = "`t`t<OwnerRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_HAS_COMPLETED_PROGRESSION_TREE_NODE`" inverse=`"true`"><Argument name=`"ProgressionTreeNodeType`">$hostNode</Argument><Argument name=`"MinDepth`">1</Argument></Requirement>$NL`t`t</OwnerRequirements>$NL"
    "`t<Modifier id=`"MA_${sfx}_RESEED_${yname}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_POPULATION`">$NL$owner`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Urban`">true</Argument><Argument name=`"Rural`">false</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_RESEED_DESCRIPTION</Argument>$NL`t</Modifier>"
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
# DESIGN (ROUTE A, 2026-06-20): flat per-CS yields are USELESS for a one-city tall player (CS count is
# tiny; improvements are 1-per-city by meta). The ONLY axis that scales for tall is POPULATION. AND the CS
# bonus system is a DRAFT from a per-type pool where most options are EXCLUSIVE (first-come, lockable by a
# rival) except ONE per type marked Shareable="true" (the "+yield to Warehouse buildings" option, repeatable).
# So: gate a PER-POP yield on having drafted that type's SHAREABLE bonus (the one we can always get), via
# REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS. The CS is the UNLOCK, your pop is the MULTIPLIER. Share-bonus id is
# uniform: CITY_STATE_<TYPE>_BONUS_<BonusAge>_7. Route A also overrides that bonus's menu DESCRIPTION text so
# the player sees our add-on (see the generated text section). VERIFY in-game: ELIGIBLE_CS_BONUS fires on DRAFT.
#
# (1) Five CITY yields, PER-POP, unlocked by drafting that type's Shareable CS bonus. EFFECT_CITY_ADJUST_
#     YIELD_PER_POPULATION (the effect the whole tall kit is built on), gated on the Shareable bonus + anti-wide.
function M-SuzerainPerPop($sfx,$shareBonus,$yield,$csType,$div) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_${csType}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_POPULATION`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS`"><Argument name=`"CityStateBonus`">$shareBonus</Argument></Requirement>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">1</Argument><Argument name=`"Divisor`">$div</Argument>$NL`t`t<Argument name=`"Urban`">true</Argument><Argument name=`"Rural`">false</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_${sfx}_NOTE_SUZERAIN</Argument>$NL`t</Modifier>"
}
# (2) DIPLOMATIC->Influence. Influence is PLAYER-level (can't ride the per-pop city effect), so EFFECT_PLAYER_
#     ADJUST_YIELD_PER_SUZERAIN (base: HOSPITALITY_MOD_SUZERAINS) grants +Amount YIELD_DIPLOMACY per TOTAL
#     suzerain (any type) - a compounding loop. Gated on the DIPLOMATIC Shareable bonus + anti-wide.
function M-SuzerainDiplo($sfx,$shareBonus,$amt) {
    "`t<Modifier id=`"MA_${sfx}_SUZ_DIPLOMATIC`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_YIELD_PER_SUZERAIN`">$NL`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_PLAYER_ELIGIBLE_CS_BONUS`"><Argument name=`"CityStateBonus`">$shareBonus</Argument></Requirement>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_DIPLOMACY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
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
# TOWN-SPEC "TEMPLE" bucket (EX-only), internalized. The base Exploration Temple town specialization grants
# +2 Great Work slots on BUILDING_TEMPLE to the connected city (SLOTS_ON_TEMPLES_IN_CITY_FROM_PROJECT,
# EFFECT_CITY_ADJUST_GREAT_WORK_SLOTS, ConstructibleType=BUILDING_TEMPLE). We give the same to the metropolis,
# gated on the religion-branch civic (Theology). RELICS are Great Works, and the kit already hoards collection
# slots, so this is the relic/religious-tourism amplifier for the Culture lane. Integer slots -> BINARY on/off
# (SOLO band = exactly 1 settlement in the hemisphere, like M-ResourceCap/M-GreatWorks), pop-tiered (T2),
# per-hemisphere (temples exist in the distant city too, unlike the homeland-only Palace slots). SlotType=ANY
# (accepts relics/codices/artifacts), matching the proven M-GreatWorks pattern.
function M-TempleSlots($sfx,$tier,$node,$pop,$amt,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate 'SOLO' $h) -join $NL
    "`t<Modifier id=`"MA_${sfx}_T${tier}_TEMPLE_SLOTS${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_GREAT_WORK_SLOTS`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"ConstructibleType`">BUILDING_TEMPLE</Argument>$NL`t`t<Argument name=`"SlotType`">GREATWORKSLOT_ANY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# TOWN-SPEC "HUB TOWN" bucket internalized. (Internal data id is PROJECT_TOWN_INN; the player-facing town
# focus is "Hub Town" - that is the correct name.) The base Hub Town routes +1 Influence (YIELD_DIPLOMACY) per
# directly CONNECTED settlement (EFFECT_CITY_ADJUST_YIELD_PER_CONNECTED_CITY) - which is ZERO for a one-city
# player. INFLUENCE CANNOT be granted as a per-population or generic city/tile yield (learned the hard way in
# the suzerain work + confirmed: no base modifier uses EFFECT_CITY_ADJUST_YIELD_PER_POPULATION with
# YIELD_DIPLOMACY). Influence is a PLAYER-level yield, emitted by: flat EFFECT_PLAYER_ADJUST_YIELD, per-building
# EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD (the primer's proven pattern), per-relationship, or per-suzerain.
# So (2026-06-21): make it ADDITIVE on the age's DIPLOMACY building and gate it BEHIND that building
# in the tree. +$amt Influence on $building (AQ Monument @ Masonry / EX Guildhall @ Guilds - both natively yield
# Influence), via EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD, gated on the building's unlock node + anti-wide. It
# shows directly on the building's yield tooltip (self-discoverable). Stacks with the flat primer + per-suzerain
# layer to fix the Deity "+5 influence" cap. Player-wide (COLLECTION_OWNER), emitted once per FanOut age.
function M-HubInfluence($sfx,$node,$building,$amt) {
    "`t<Modifier id=`"MA_${sfx}_HUB_INFLUENCE`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_DIPLOMACY</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"ConstructibleType`">$building</Argument>$NL`t</Modifier>"
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
# TOWN-SPEC "Fort Town" bucket internalized (DISTINCT MECHANIC = durability, no yield overlap; we skip Fort's
# minor gold-on-fortifications yield per the overlap rule). For an outnumbered one-city defender. Player-rooted
# collections proven via base traditions/traits: COLLECTION_PLAYER_DISTRICTS + EFFECT_DISTRICT_ADJUST_TOTAL_HEALTH
# (e.g. NORMAN_SYNCRETISM_MOD_WALL_HEALTH, CARD_AT_WALL_HEALTH); COLLECTION_PLAYER_UNITS +
# EFFECT_UNIT_ADJUST_HEAL_PER_TURN (e.g. DE_FACTO_MOD_HEALING) - so both deliver through the player attach
# wrapper. Gated on the Military-deepen node + anti-wide in OwnerRequirements. Player-wide, emitted once.
function M-FortHealth($sfx,$node,$amt) {
    "`t<Modifier id=`"MA_${sfx}_FORT_HEALTH`" collection=`"COLLECTION_PLAYER_DISTRICTS`" effect=`"EFFECT_DISTRICT_ADJUST_TOTAL_HEALTH`">$NL$(OwnerNodeAntiWide $node)`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
function M-FortHealing($sfx,$node,$amt) {
    "`t<Modifier id=`"MA_${sfx}_FORT_HEALING`" collection=`"COLLECTION_PLAYER_UNITS`" effect=`"EFFECT_UNIT_ADJUST_HEAL_PER_TURN`">$NL$(OwnerNodeAntiWide $node)`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t</Modifier>"
}
# TOWN-SPEC WAREHOUSE buckets (Farming/Fishing = rural Food, Mining = rural Production, Trade Outpost = resource
# Happiness). Powers up RURAL tiles via the base warehouse-yield-change handles. COLLECTION_PLAYER_CITIES +
# EFFECT_CITY_GRANT_WAREHOUSE_YIELD (proven, 100+ base uses). DISTINCT from the flat under-cap Food/Production
# (player yield, not a tile boost) - no double-count. Gated on the matching node + CITY_IS_CITY + anti-wide.
function M-Warehouse($sfx,$idname,$node,$handles) {
    "`t<Modifier id=`"MA_${sfx}_${idname}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_GRANT_WAREHOUSE_YIELD`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"WarehouseYieldChange`">$handles</Argument>$NL`t</Modifier>"
}
# TOWN-SPEC "Religious Site" Temple bucket, happiness half: +Happiness on every Building. EFFECT_PLAYER_ADJUST_
# CONSTRUCTIBLE_YIELD with ConstructibleClass=BUILDING (proven, COLLECTION_OWNER/player). Gated on the religion node.
function M-BuildingHappiness($sfx,$node,$amt) {
    "`t<Modifier id=`"MA_${sfx}_RELIGIOUS_HAPPINESS`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL$(Settle $tallCap $true 'false' '')$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"ConstructibleClass`">BUILDING</Argument>$NL`t</Modifier>"
}
# TOWN-SPEC plot-yield buckets (Fort gold-on-fortifications + Resort appeal/Natural-Wonder tiles). COLLECTION_
# PLAYER_PLOT_YIELDS + EFFECT_PLOT_ADJUST_YIELD (player-rooted, 100+ base uses). $reqXml = the SubjectRequirements
# plot filter (fortification / appeal / natural wonder); $yieldXml = the yield arguments. Node + anti-wide owner-gated.
function M-PlotYield($sfx,$idname,$node,$reqXml,$yieldXml,$minDepth=1) {
    "`t<Modifier id=`"MA_${sfx}_${idname}`" collection=`"COLLECTION_PLAYER_PLOT_YIELDS`" effect=`"EFFECT_PLOT_ADJUST_YIELD`">$NL$(OwnerNodeAntiWide $node $minDepth)`t`t<SubjectRequirements>$NL$reqXml$NL`t`t</SubjectRequirements>$NL$yieldXml$NL`t</Modifier>"
}
# ITEM 6 (relic/Culture amplifier): +Yield per Great Work in the city. Relics/Codices/Artifacts/Art are all
# Great Works, and the kit hoards GW slots (Palace + the Temple "Religious Site" slots + collection slots), so
# this directly rewards the hoard - the amplifier for the surviving Culture/relic lane (the one that held at
# Deity). EFFECT_CITY_ADJUST_YIELD_PER_GREAT_WORK (YieldType, Amount, Tooltip; base proof GREATPERSON_CODEX_
# SCIENCE = +1 Science per GW). City effect -> COLLECTION_PLAYER_CITIES, per-hemisphere, pop-tiered (T2 so it
# pairs with the Temple relic slots), SOLO hard-cutoff. EX-ONLY in practice (emitted only where TempleSlots is
# set) and gated on the religion node passed in (Theology) - relics are the cultural Great Works + arrive in the
# religion age; AQ Great Works are Codices (science), so culture-per-GW is deliberately NOT in Antiquity.
function M-GreatWorkYield($sfx,$node,$pop,$yield,$amt,$hemi,$dl) {
    $h = HemiArg $hemi; $hc = HemiCityReq $hemi
    $gate = (BandGate 'SOLO' $h) -join $NL
    $yname = ($yield -replace '^YIELD_','')
    "`t<Modifier id=`"MA_${sfx}_GW_${yname}${dl}`" collection=`"COLLECTION_PLAYER_CITIES`" effect=`"EFFECT_CITY_ADJUST_YIELD_PER_GREAT_WORK`">$NL$(Owner $node)`t`t<SubjectRequirements>$NL`t`t`t<Requirement type=`"REQUIREMENT_CITY_IS_CITY`"/>$NL$(PopReq $pop)$hc$gate$NL`t`t</SubjectRequirements>$NL`t`t<Argument name=`"YieldType`">$yield</Argument>$NL`t`t<Argument name=`"Amount`">$amt</Argument>$NL`t`t<Argument name=`"Tooltip`">LOC_MA_${sfx}_NOTE_RELIGION</Argument>$NL`t</Modifier>"
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

foreach ($age in $ages) {
    $sfx=$age.Sfx; $node=$age.Node; $pops=$age.Pops; $N=$age.Nodes
    # Secondary-layer tall cap (Suzerain / town-spec / trade / hub / reseed): hard 1-per-hemisphere like the core.
    # AQ has no Distant Lands -> at most 1 settlement (fewer than 2); EX/MO -> at most 1 per hemisphere = 2 total
    # (fewer than 3). At the next settlement these turn OFF (matching the core SOLO cutoff). The specialist CAP +
    # the 2 safety nets keep their separate lenient non-revoking gate (Settle 4/5 'true') to avoid an over-cap spiral.
    $tallCap = if ($age.Distant) { 3 } else { 2 }
    # NONE for AQ (no Distant Lands); HL (+ DL) for EX/MO.
    $hemis = if ($age.Distant) { @('HL','DL') } else { @('NONE') }

    $out = @()
    $out += '<?xml version="1.0" encoding="utf-8"?>'
    $out += "<!-- Metropolis Ascendant - $($age.AgeName) modifiers. GENERATED by tools/gen-ascendant.ps1 - do not hand-edit.$(if($TestMode){' [TEST BUILD: pop thresholds 2/4/6, tech gate removed - for fast validation only]'})"
    $out += "     PER-HEMISPHERE model (item K) + HARD CUTOFF (2026-06-21): rewards are BINARY per hemisphere -"
    $out += "     FULL at exactly 1 settlement in the hemisphere, NOTHING at 2+ (no geometric taper). Rewards"
    $out += "     count ALL settlements (towns included); the specialist CAP + the 2 safety nets count CITIES"
    $out += "     ONLY and keep a lenient non-revoking gate (off at 4+) so a slip never strands specialists."
    if ($age.Distant) {
        $out += "     Two sets: HOMELAND (REQUIREMENT_CITY_IS_DISTANT_LANDS inverse + OnlyHomelands) and DISTANT-LANDS"
        $out += "     (_DL ids; REQUIREMENT_CITY_IS_DISTANT_LANDS + OnlyDistantlands). GREAT_WORKS (capital/Palace) and"
        $out += "     COLLECTION_SLOTS (constructibles, can take no settlement req) are homeland-set / player-wide only."
    } else {
        $out += "     Antiquity has no Distant Lands, so this is a single unscoped set (plain total settlement count)."
    }
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
        $noteId  = if ($note.Key -eq 'ALL') { "MA_${sfx}_UNLOCK_NOTE" } else { "MA_${sfx}_NOTE_$($note.Key)" }
        $noteLoc = if ($note.Key -eq 'ALL') { 'LOC_MA_UNLOCK_NOTE' }     else { "LOC_MA_${sfx}_NOTE_$($note.Key)" }   # per-age tag so EX/MO numbers differ from AQ
        $out += "`t<Modifier id=`"$noteId`" collection=`"COLLECTION_OWNER`" effect=`"EFFECT_PLAYER_ADJUST_SETTLEMENT_CAP`" permanent=`"true`">$NL`t`t<Argument name=`"Amount`">0</Argument>$NL`t`t<String context=`"Description`">$noteLoc</String>$NL`t</Modifier>"
    }
    $out += ''

    $wrapIds = @()
    foreach ($hemi in $hemis) {
        $dl = if ($hemi -eq 'DL') { '_DL' } else { '' }
        if ($hemi -eq 'HL')   { $out += "`t<!-- ===================== HOMELAND hemisphere set ===================== -->" }
        elseif ($hemi -eq 'DL'){ $out += "`t<!-- ==================== DISTANT-LANDS hemisphere set ==================== -->" }

        # TIER 1
        $out += "`t<!-- TIER 1 (Urban pop >= $($pops[0]))$(if($dl){' - distant lands'}) -->"
        $out += (M-WorkerCap $sfx 1 $N.Spine $pops[0] $hemi $dl); $wrapIds += "MA_${sfx}_T1_WORKER_CAP${dl}"
        $out += (M-Upkeep $sfx $pops[0] $hemi $dl);            $wrapIds += "MA_${sfx}_T1_SPECIALIST_UPKEEP${dl}"
        $out += (M-Happiness $sfx $pops[0] $age.Happiness $hemi $dl); $wrapIds += "MA_${sfx}_T1_HAPPINESS${dl}"
        $out += (M-ResourceCap $sfx 1 $N.Economic $pops[0] $age.ResCap[0] $hemi $dl); $wrapIds += "MA_${sfx}_T1_RESOURCE_CAP${dl}"
        # IDEA 1: happiness-stage payoff lane (core mechanic; T1 pop floor; SOLO + hemisphere-scoped). Joyous +
        # Ecstatic gates STACK. Two stage-yields (Science+Culture) x two stages = 4 modifiers per hemisphere.
        $stageNode = @{ 'YIELD_SCIENCE'=$N.Science; 'YIELD_CULTURE'=$N.Culture }   # advertise each half on its domain node
        foreach ($yld in $stageYields) {
            $yn = ($yld -replace '^YIELD_',''); $sn = $stageNode[$yld]
            $out += (M-StagePayoff $sfx $sn $pops[0] 'HAPPINESS_STAGE_JOYOUS'   $yld $stageJoyousDiv   $hemi $dl); $wrapIds += "MA_${sfx}_STAGE_JOYOUS_${yn}${dl}"
            $out += (M-StagePayoff $sfx $sn $pops[0] 'HAPPINESS_STAGE_ECSTATIC' $yld $stageEcstaticDiv $hemi $dl); $wrapIds += "MA_${sfx}_STAGE_ECSTATIC_${yn}${dl}"
        }

        # TIER 2
        $out += "`t<!-- TIER 2 (Urban pop >= $($pops[1]))$(if($dl){' - distant lands'}) -->"
        $out += (M-WorkerCap $sfx 2 $N.Spine $pops[1] $hemi $dl); $wrapIds += "MA_${sfx}_T2_WORKER_CAP${dl}"
        for ($b=0; $b -lt $bandList.Count; $b++) {
            $band=$bandList[$b]
            $out += (M-Wonders $sfx $N.Wonders $pops[1] $band $age.Wonders[$b] $hemi $dl)
            $wrapIds += "MA_${sfx}_T2_WONDERS_${band}${dl}"
        }
        if ($hemi -ne 'DL') {   # great works = homeland/capital only
            $out += (M-GreatWorks $sfx $N.Science $pops[1] $age.GW $hemi); $wrapIds += "MA_${sfx}_T2_GREAT_WORKS"
        }
        $out += (M-ResourceCap $sfx 2 $N.Economic $pops[1] $age.ResCap[1] $hemi $dl); $wrapIds += "MA_${sfx}_T2_RESOURCE_CAP${dl}"
        # TOWN-SPEC Temple bucket (EX-only): +Great Work slots on Temples (relic storage) on the religion node.
        # Per-hemisphere (the distant city's temples too); integer/binary SOLO band like the other slot grants.
        if ($age.TempleSlots) {
            $out += (M-TempleSlots $sfx 2 $N.Religion $pops[1] $age.TempleSlots $hemi $dl); $wrapIds += "MA_${sfx}_T2_TEMPLE_SLOTS${dl}"
            # ITEM 6: relic/Great-Work Culture amplifier - EX-only (RELICS are the cultural Great Works and only
            # arrive in the religion age; in AQ Great Works = Codices = science-flavored, so culture-per-GW would
            # be off-theme AND over-boost AQ culture, which is already dominant). Gated on the SAME religion node
            # (Theology) as the Temple relic-slots so relic STORAGE and relic->CULTURE travel together; the effect
            # can't filter to relics-only, but EX hoards are relic-heavy. Auto-extends to MO when MO gets TempleSlots.
            $out += (M-GreatWorkYield $sfx $N.Religion $pops[1] 'YIELD_CULTURE' $gwCultureAmt $hemi $dl); $wrapIds += "MA_${sfx}_GW_CULTURE${dl}"
        }

        # TIER 3
        $out += "`t<!-- TIER 3 (Urban pop >= $($pops[2]))$(if($dl){' - distant lands'}) -->"
        $out += (M-WorkerCap $sfx 3 $N.Spine $pops[2] $hemi $dl); $wrapIds += "MA_${sfx}_T3_WORKER_CAP${dl}"
        # Economic DEEPEN: tier-3 resource cap moves to the EconomicDeep node (Wheel) - research Wheel to
        # deepen your resource economy on top of Currency's tier 1-2 cap.
        $out += (M-ResourceCap $sfx 3 $N.EconomicDeep $pops[2] $age.ResCap[2] $hemi $dl); $wrapIds += "MA_${sfx}_T3_RESOURCE_CAP${dl}"
        if ($hemi -ne 'DL') {   # collection slots + trade routes = player-wide, homeland set only
            $out += (M-CollectionSlots $sfx $N.Science $age.Collection); $wrapIds += "MA_${sfx}_T3_COLLECTION_SLOTS"
            $out += (M-TradeRoutes $sfx $N.Commerce $age.Trade); $wrapIds += "MA_${sfx}_TRADE_ROUTES"
        }
        # Two-node model: per-pop yields are each domain's DEEPEN node. Science -> Mathematics; Culture -> Mysticism civic.
        $perPopNode = @{ 'YIELD_SCIENCE'=$N.ScienceDeep; 'YIELD_CULTURE'=$N.CultureDeep }
        foreach ($yld in @('YIELD_SCIENCE','YIELD_CULTURE')) {
            $yname = ($yld -replace '^YIELD_','')
            for ($b=0; $b -lt $bandList.Count; $b++) {
                $band=$bandList[$b]
                $out += (M-PerPop $sfx $perPopNode[$yld] $pops[2] $band $yld $perPopDiv[$band] $hemi $dl)
                $wrapIds += "MA_${sfx}_T3_${yname}_${band}${dl}"
            }
        }
        # ---- FAN-OUT EXTRAS (Antiquity only; FanOut=$true). ----
        if ($age.FanOut -and $hemi -ne 'DL') {
            $out += "`t<!-- FAN-OUT: Military production-per-pop ($($N.Military)) + combat strength ($($N.MilitaryDeep));"
            $out += "`t     Qajar under-settlement-cap Food ($($N.FoodCap)) / Production ($($N.ProdCap)); trade-route RANGE ($($N.Commerce)). -->"
            for ($b=0; $b -lt $bandList.Count; $b++) {
                $band=$bandList[$b]
                $out += (M-PerPop $sfx $N.Military $pops[2] $band 'YIELD_PRODUCTION' $perPopDiv[$band] $hemi $dl)
                $wrapIds += "MA_${sfx}_T3_PRODUCTION_${band}${dl}"
            }
            $out += (M-CombatStrength $sfx $N.MilitaryDeep $age.MilStrength); $wrapIds += "MA_${sfx}_T3_COMBAT_STRENGTH"
            $out += (M-UnderCapYield $sfx 'YIELD_FOOD' $age.UnderCapAmount $N.FoodCap);       $wrapIds += "MA_${sfx}_UNDER_CAP_FOOD"
            $out += (M-UnderCapYield $sfx 'YIELD_PRODUCTION' $age.UnderCapAmount $N.ProdCap); $wrapIds += "MA_${sfx}_UNDER_CAP_PRODUCTION"
            $out += (M-TradeRange $sfx $N.Commerce 'DOMAIN_LAND' $age.TradeRange); $wrapIds += "MA_${sfx}_TRADE_RANGE_LAND"
            $out += (M-TradeRange $sfx $N.Commerce 'DOMAIN_SEA' $age.TradeRange);  $wrapIds += "MA_${sfx}_TRADE_RANGE_SEA"
        }
        $out += ''
    }

    # ---- AGE-TRANSITION RESEED (EX/MO only; player-wide, not hemisphere-scoped, emitted once) ----
    # See M-Reseed: per-pop Science+Culture bridge live from age turn 1, off once the host node is researched.
    if ($age.Sfx -ne 'AQ') {
        $out += "`t<!-- RESEED: turn-1 per-pop Science+Culture bridge for the tall player; switches OFF once the"
        $out += "`t     host node ($($age.Node)) is researched and the gated kit takes over. Fills the early-age valley. -->"
        $out += (M-Reseed $sfx $age.Node $pops[0] 'YIELD_SCIENCE' $perPopDiv.SOLO); $wrapIds += "MA_${sfx}_RESEED_SCIENCE"
        $out += (M-Reseed $sfx $age.Node $pops[0] 'YIELD_CULTURE' $perPopDiv.SOLO); $wrapIds += "MA_${sfx}_RESEED_CULTURE"
        $out += ''
    }

    # ---- SUZERAIN LAYER (Phase 3; FanOut ages only; player-wide, emitted once) ----
    # See M-Suzerain et al.: auto-scaling yields per suzerained CS type + free pop per Expansionist + a flat
    # influence primer to fund winning the first city-states. The width-substitute for a one-city empire.
    if ($age.FanOut) {
        $ba = $age.BonusAge
        $out += "`t<!-- SUZERAIN (Route A): PER-POP yield unlocked by drafting each type's SHAREABLE city-state bonus"
        $out += "`t     (CITY_STATE_<TYPE>_BONUS_${ba}_7, the one repeatable option). +Influence per total suzerain"
        $out += "`t     (Diplomatic shareable); flat Influence primer. (Free-pop removed - one-shot grant can't gate.) -->"
        foreach ($cs in $suzCity.Keys) {
            $share = "CITY_STATE_${cs}_BONUS_${ba}_7"
            $out += (M-SuzerainPerPop $sfx $share $suzCity[$cs] $cs $suzPerPopDiv); $wrapIds += "MA_${sfx}_SUZ_${cs}"
        }
        $out += (M-SuzerainDiplo $sfx "CITY_STATE_DIPLOMATIC_BONUS_${ba}_7" $suzDiploAmt); $wrapIds += "MA_${sfx}_SUZ_DIPLOMATIC"
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
    if ($age.FanOut) {
        $out += "`t<!-- TOWN-SPECIALIZATION ROLL-IN (player-wide, distinct from the Suzerain layer). Each bucket"
        $out += "`t     matches a base Town focus, delivered to the metropolis & gated behind a thematic node:"
        $out += "`t       Hub Town       -> +Influence on the Diplomacy building (its unlock node)"
        $out += "`t       Fort Town      -> +District HP + Unit heal + Gold on Fortifications (own dedicated military node)"
        $out += "`t       Farming/Fishing-> +Food on rural tiles (FoodCap node);  Mining -> +Prod on rural tiles (ProdCap)"
        $out += "`t       Trade Outpost  -> +Happiness from resources warehouse (Commerce node)"
        $out += "`t       Religious Site -> +Happiness per Building (religion node; pairs with the temple slots above)"
        $out += "`t       Resort         -> +Gold/Happiness on appeal tiles + % all yields on Natural-Wonder tiles (Wonders node) -->"
        # -- Hub Town --
        $out += (M-HubInfluence $sfx $age.HubNode $age.HubBuilding $hubInfluenceAmt);      $wrapIds += "MA_${sfx}_HUB_INFLUENCE"
        # -- Fort Town (durability + gold on fortifications) -- on its OWN node ($age.FortNode), off the
        #    overloaded Military-deepen node (which keeps just combat strength).
        $out += (M-FortHealth $sfx $age.FortNode $fortHealth);                             $wrapIds += "MA_${sfx}_FORT_HEALTH"
        $out += (M-FortHealing $sfx $age.FortNode $fortHeal);                              $wrapIds += "MA_${sfx}_FORT_HEALING"
        $fortGoldReq = "`t`t`t<Requirement type=`"REQUIREMENT_PLOT_HAS_CONSTRUCTIBLE`"><Argument name=`"Tag`">FORTIFICATION</Argument><Argument name=`"CurrentAgeOnly`">false</Argument></Requirement>"
        $fortGoldYld = "`t`t<Argument name=`"YieldType`">YIELD_GOLD</Argument>$NL`t`t<Argument name=`"Amount`">$fortGold</Argument>"
        $out += (M-PlotYield $sfx 'FORT_GOLD' $age.FortNode $fortGoldReq $fortGoldYld);    $wrapIds += "MA_${sfx}_FORT_GOLD"
        # -- Farming/Fishing + Mining + Trade-Outpost warehouses (power up rural tiles / resource happiness) --
        $out += (M-Warehouse $sfx 'WAREHOUSE_FOOD' $N.FoodCap $warehouse[$sfx].Food);       $wrapIds += "MA_${sfx}_WAREHOUSE_FOOD"
        $out += (M-Warehouse $sfx 'WAREHOUSE_PRODUCTION' $N.ProdCap $warehouse[$sfx].Prod); $wrapIds += "MA_${sfx}_WAREHOUSE_PRODUCTION"
        $out += (M-Warehouse $sfx 'WAREHOUSE_HAPPINESS' $N.Commerce $warehouse[$sfx].Happy);$wrapIds += "MA_${sfx}_WAREHOUSE_HAPPINESS"
        # -- Religious Site happiness (EX only - the religion node only exists where TempleSlots is set) --
        if ($age.TempleSlots) {
            $out += (M-BuildingHappiness $sfx $N.Religion $religiousHappy);                 $wrapIds += "MA_${sfx}_RELIGIOUS_HAPPINESS"
        }
        # -- Resort (appeal tiles + Natural-Wonder tiles; the NW % self-targets so it only pays near a wonder) --
        #    On the Wonders node's MASTERY (MinDepth=2), so that node's first tier carries only wonder-%.
        $resortAppealReq = "`t`t`t<Requirement type=`"REQUIREMENT_PLOT_HAS_APPEAL`"><Argument name=`"UseAppealHappinessThreshold`">true</Argument></Requirement>"
        $resortAppealYld = "`t`t<Argument name=`"YieldType`">YIELD_GOLD, YIELD_HAPPINESS</Argument>$NL`t`t<Argument name=`"Amount`">$resortAppeal</Argument>"
        $out += (M-PlotYield $sfx 'RESORT_APPEAL' $N.Wonders $resortAppealReq $resortAppealYld 2); $wrapIds += "MA_${sfx}_RESORT_APPEAL"
        $resortNWReq = "`t`t`t<Requirement type=`"REQUIREMENT_PLOT_IS_NATURAL_WONDER`"/>"
        $resortNWYld = "`t`t<Argument name=`"YieldType`">YIELD_FOOD, YIELD_PRODUCTION, YIELD_GOLD, YIELD_SCIENCE, YIELD_CULTURE, YIELD_HAPPINESS, YIELD_DIPLOMACY</Argument>$NL`t`t<Argument name=`"Percent`">$resortNWPercent</Argument>"
        $out += (M-PlotYield $sfx 'RESORT_NATURAL_WONDER' $N.Wonders $resortNWReq $resortNWYld 2); $wrapIds += "MA_${sfx}_RESORT_NATURAL_WONDER"
        $out += ''
    }

    # ---- adjacency block (generated) ----
    $out += "`t<!-- ADJACENCY REWARD: boost ALL 7 Science/Culture adjacency rules across the 3 pop tiers,"
    $out += "`t     HARD CUTOFF (full +1/+2/+3 at exactly 1 settlement in the hemisphere, nothing at 2+)."
    $out += "`t     On-design under 1.4.0: specialists pay out 100% of tile adjacency, so each point added here is"
    $out += "`t     also delivered again by every specialist placed. EFFECT_CITY_ADJUST_ADJACENCY_FLAT_AMOUNT. -->"
    foreach ($hemi in $hemis) {
        $dl = if ($hemi -eq 'DL') { '_DL' } else { '' }
        if ($hemi -eq 'HL')    { $out += "`t<!-- ADJ - HOMELAND -->" }
        elseif ($hemi -eq 'DL'){ $out += "`t<!-- ADJ - DISTANT LANDS -->" }
        for ($t=1; $t -le 3; $t++) {
            $pop=$pops[$t-1]
            $out += "`t<!-- Adjacency tier $t (pop >= $pop)$(if($dl){' - distant lands'}) -->"
            foreach ($rule in $adjRules.Keys) {
                $adjNode = $N[$ruleDomain[$rule]]   # Science rules -> Science node (Writing); Culture rules -> Culture node (Masonry)
                foreach ($band in $bandList) {
                    $frag=$adjRules[$rule]
                    $out += (M-Adjacency $sfx $t $adjNode $pop $rule $band $adjDiv[$band] $hemi $dl)
                    $wrapIds += "MA_${sfx}_T${t}_ADJ_${frag}_${band}${dl}"
                }
            }
        }
    }
    $out += ''

    # ---- ATTACH_ALL delivery wrapper ----
    $out += "`t<!-- DELIVERY WRAPPER: a COLLECTION_PLAYER_CITIES modifier bound directly via GameModifiers never"
    $out += "`t     attaches (game-level has no `"the player`" context). The base game wraps player bonuses in a"
    $out += "`t     COLLECTION_MAJOR_PLAYERS + EFFECT_ATTACH_MODIFIERS modifier; traditions.xml binds ONLY this"
    $out += "`t     wrapper, which attaches every modifier below to each major player so they resolve their own"
    $out += "`t     collection + tech-node + pop + per-hemisphere anti-wide gates. -->"
    $out += "`t<Modifier id=`"MA_${sfx}_ATTACH_ALL`" collection=`"COLLECTION_MAJOR_PLAYERS`" effect=`"EFFECT_ATTACH_MODIFIERS`">"
    $out += "`t`t<Argument name=`"ModifierId`">$($wrapIds -join ', ')</Argument>"
    $out += "`t</Modifier>"
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
}

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
    [ordered]@{
      SCIENCE  = "+1 [icon:YIELD_SCIENCE] Science adjacency per Tier (max +3); +$gw Palace and +$col per-building Great Work slots (T2)."
      SCIENCE2 = "+1 [icon:YIELD_SCIENCE] Science per $ppd $upop (T3)."
      CULTURE  = "+$($w[0])% [icon:YIELD_PRODUCTION] Wonder Production (T2)."
      RESORT   = "+$resortAppeal [icon:YIELD_GOLD] Gold and [icon:YIELD_HAPPINESS] Happiness on Appealing tiles, and +$resortNWPercent% to all yields from tiles with a Natural Wonder."
      CULTURE2 = "+1 [icon:YIELD_CULTURE] Culture adjacency per Tier (max +3); +1 [icon:YIELD_CULTURE] Culture per $ppd $upop (T3)."
      ECONOMIC = "+1 Specialist slot per district per Tier (max +3, Cities only); +$rcA Resource capacity (T1-T2, max +$rcCur). Specialists also cost 50% less [icon:YIELD_FOOD] Food and [icon:YIELD_HAPPINESS] Happiness to maintain until this Settlement is Ecstatic."
      STAGE_SCIENCE = "While Joyous or happier: +1 [icon:YIELD_SCIENCE] Science per $stageJoyousDiv $upop, increasing further while Ecstatic."
      STAGE_CULTURE = "While Joyous or happier: +1 [icon:YIELD_CULTURE] Culture per $stageJoyousDiv $upop, increasing further while Ecstatic."
      ECONOMIC2= "+$rcC Resource capacity (T3; +$rcTot total)."
      TRADE    = "+$tr Trade Routes, +$trg Trade Route range (land and sea), and +[icon:YIELD_HAPPINESS] Happiness from Resources."
      MILITARY = "+1 [icon:YIELD_PRODUCTION] Production per $ppd $upop (T3)."
      MILITARY2= "+$ms Combat Strength in all combat."
      FORT     = "+$fortHealth District HP, +$fortHeal Unit healing per turn, and +$fortGold [icon:YIELD_GOLD] Gold on Fortifications."
      FOODCAP  = "+$uc [icon:YIELD_FOOD] Food per settlement under your Settlement Cap, and +[icon:YIELD_FOOD] Food on worked Farms, Pastures, Plantations and Fishing Boats."
      PRODCAP  = "+$uc [icon:YIELD_PRODUCTION] Production per settlement under your Settlement Cap, and +[icon:YIELD_PRODUCTION] Production on worked Camps, Mines, Quarries and Woodcutters."
      RELIGION = "+$ts Great Work slots on Temples (Relics, Codices, Artifacts, Great Works), +$religiousHappy [icon:YIELD_HAPPINESS] Happiness per Building, and +$gwCultureAmt [icon:YIELD_CULTURE] Culture per Great Work in this city (T2)."
      SUZERAIN = "Suzerain bonuses scale with your [icon:YIELD_POPULATION] Population. Draft a city-state's repeatable (Shareable) bonus to gain +1 of its yield per $suzPerPopDiv [icon:YIELD_POPULATION] Pop ([icon:YIELD_SCIENCE]/[icon:YIELD_CULTURE]/[icon:YIELD_PRODUCTION]/[icon:YIELD_GOLD]/[icon:YIELD_FOOD]), or +$suzDiploAmt [icon:YIELD_DIPLOMACY] Influence per Suzerain (Diplomatic). Each Suzerain grants +$suzResCapAmt Resource capacity; Economic ones add +$suzTradeRangeAmt Trade Route range."
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
            $t = $nt[$note.Key] -replace '&','&amp;' -replace '<(?![A-Za-z/])','&lt;'
            $tl += "`t`t<Row Tag=`"LOC_MA_${sfxA}_NOTE_$($note.Key)`">"
            $tl += "`t`t`t<Text>$t</Text>"
            $tl += "`t`t</Row>"
            $noteRowCount++
        }
    }
    $tl += "`t</EnglishText>"
    # ROUTE A discoverability: OVERRIDE each type's SHAREABLE city-state bonus DESCRIPTION so the draft menu
    # advertises our per-pop add-on. MUST use <LocalizedText><Replace Tag=... Language="en_US"> (upsert, the
    # exact base-game l10n pattern) - NOT <EnglishText><Row>, which INSERTs a duplicate of the existing base
    # tag -> load error -> rollback -> CRASH (learned the hard way 2026-06-20). Tag = CITY_STATE_<TYPE>_BONUS_
    # <BonusAge>_7_DESCRIPTION (base tag, no LOC_ prefix). Because <Replace> overwrites the WHOLE string, we
    # PREPEND the real base description (read live from the install - see below) so the player still sees what
    # the bonus does, then add our tall add-on. No [B] markup (unproven in this UI). One set per FanOut age.
    $suzMenu = [ordered]@{
        SCIENTIFIC=@{Icon='YIELD_SCIENCE';Name='Science'}; CULTURAL=@{Icon='YIELD_CULTURE';Name='Culture'}
        MILITARISTIC=@{Icon='YIELD_PRODUCTION';Name='Production'}; ECONOMIC=@{Icon='YIELD_GOLD';Name='Gold'}
        EXPANSIONIST=@{Icon='YIELD_FOOD';Name='Food'}
    }
    function Find-Civ7Root {
        if ($env:CIV7_ROOT -and (Test-Path $env:CIV7_ROOT)) { return $env:CIV7_ROOT }
        $libs = @("C:\Program Files (x86)\Steam", "C:\Program Files\Steam")
        $vdf = "C:\Program Files (x86)\Steam\steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) { foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s*"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\','\') } }
        foreach ($lib in $libs) { $p = Join-Path $lib "steamapps\common\Sid Meier's Civilization VII"; if (Test-Path $p) { return $p } }
        return $null
    }
    $civ7Root = Find-Civ7Root
    if (-not $civ7Root) { Write-Host "  suzerain menu: Civ VII install not found - skipping base-text prepend (set CIV7_ROOT); base descriptions will show unmodified." }
    $tl += "`t<LocalizedText>"
    foreach ($fa in ($ages | Where-Object { $_.FanOut })) {
        $ba = $fa.BonusAge
        # PREPEND the real base CS-bonus description (what the bonus does) + our tall add-on, instead of clobbering
        # it. Base text is read live from the install (age-<key>\text\en_us\IndependentsText.xml) so it never goes
        # stale; its trailing "...chosen by multiple Civilizations." already conveys "repeatable", so we drop ours.
        $baseTxt = @{}
        if ($civ7Root) {
            $indFile = Join-Path $civ7Root "Base\modules\age-$($fa.Key)\text\en_us\IndependentsText.xml"
            if (Test-Path $indFile) {
                $raw = Get-Content -LiteralPath $indFile -Raw
                foreach ($cs in (@($suzMenu.Keys) + 'DIPLOMATIC')) {
                    $m = [regex]::Match($raw, ("Tag=`"CITY_STATE_{0}_BONUS_{1}_7_DESCRIPTION`".*?<Text>(.*?)</Text>" -f $cs, $ba), 'Singleline')
                    if ($m.Success) { $baseTxt[$cs] = ($m.Groups[1].Value.Trim() -replace '&','&amp;') }
                }
            }
        }
        foreach ($cs in $suzMenu.Keys) {
            if (-not $baseTxt.ContainsKey($cs)) { continue }   # base text not found -> leave the base description untouched
            $mi = $suzMenu[$cs]
            $txt = $baseTxt[$cs] + "[N][N]Metropolis Ascendant: while you stay tall (one city per hemisphere), each of your cities also earns +1 [icon:$($mi.Icon)] $($mi.Name) for every $suzPerPopDiv [icon:YIELD_POPULATION] Population it has - a dense city makes this Suzerain bonus grow with it."
            $tl += "`t`t<Replace Tag=`"CITY_STATE_${cs}_BONUS_${ba}_7_DESCRIPTION`" Language=`"en_US`"><Text>$txt</Text></Replace>"
        }
        if ($baseTxt.ContainsKey('DIPLOMATIC')) {
            $dtxt = $baseTxt['DIPLOMATIC'] + "[N][N]Metropolis Ascendant: while you stay tall (one city per hemisphere), you also earn +$suzDiploAmt [icon:YIELD_DIPLOMACY] Influence per turn for every city-state you are Suzerain of - compounding your diplomacy."
            $tl += "`t`t<Replace Tag=`"CITY_STATE_DIPLOMATIC_BONUS_${ba}_7_DESCRIPTION`" Language=`"en_US`"><Text>$dtxt</Text></Replace>"
        }
    }
    $tl += "`t</LocalizedText>"
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
    $intro = "Every scaling bonus is at FULL strength with one settlement per hemisphere and OFF at two or more. Bonuses tier up as your city's Urban Population crosses three thresholds (T1 / T2 / T3); mastery bonuses unlock on a node's Mastery panel."
    $bb = @('[h1]Metropolis Ascendant - Full Bonus List[/h1]', "[i]Auto-generated from the mod's data, so it matches the in-game tech and civic node notes exactly.[/i]", $intro)
    $md = @('# Metropolis Ascendant - Full Bonus List','',"*Auto-generated from the mod's data, so it matches the in-game tech and civic node notes exactly.*",'',$intro)
    foreach ($a in $ages) {
        $hdr = "$($a.AgeName) (Population tiers T1 / T2 / T3 = $($a.Pops -join ' / '))"
        $bb += @('', "[h2]$hdr[/h2]")
        $md += @('', "## $hdr", '')
        if ($a.FanOut) {
            $ntA = Build-NoteText $a
            $bb += '[list]'
            foreach ($note in $a.Notes) {
                if ($note.Key -eq 'ALL') { continue }
                $nm = Get-NodeName $note.Node
                $mast = if ($note.Depth -and $note.Depth -ge 2) { ' - Mastery' } else { '' }
                $txt = Format-Note $ntA[$note.Key]
                $bb += "[*][b]$($nm.Name)$mast[/b] ($($nm.Kind)): $txt"
                $md += "- **$($nm.Name)$mast** ($($nm.Kind)): $txt"
            }
            $bb += '[/list]'
        } else {
            $g = "Researching $($a.TechName) unlocks the full Metropolis Ascendant suite for the $($a.AgeName) age - science, culture, economic and military bonuses plus the density and Suzerain layers - all scaling with your city's Urban Population. (A per-node breakdown arrives when the $($a.AgeName) fan-out lands.)"
            $bb += $g; $md += $g
        }
    }
    $foundation = "Always on, no research needed: bonus Happiness and reduced specialist upkeep that grow with your city, plus +$suzPrimer Influence per turn to help you win your first city-states."
    $bb += @('', '[h2]Foundations[/h2]', $foundation)
    $md += @('', '## Foundations', '', $foundation)
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
# ---- SYNC hand-authored docs (tier thresholds + tested-on version are single-sourced from the config) ----
# Keeps the player-facing numbers in lockstep with $ages / $testedVersion: the modinfo <Description> tiers
# sentence + version, and the mod README's tiers table + version. Prose stays hand-authored; only the
# numbers/table are rewritten, so retuning Pops or bumping $testedVersion can never leave a stale doc.
$tierInline = (($ages | ForEach-Object { "$($_.Pops -join ' / ') in $($_.AgeName)" }) -join ', ')
$miFile = Join-Path $modDir "$modName.modinfo"
if (Test-Path $miFile) {
    $mt = Get-Content -LiteralPath $miFile -Raw
    $mt = $mt -replace 'Urban Population thresholds: .*? in Modern\.', "Urban Population thresholds: $tierInline."
    $mt = $mt -replace 'Built and tested on Civilization VII [0-9]+(?:\.[0-9]+)*\.?', "Built and tested on Civilization VII $testedVersion."
    Set-Content -LiteralPath $miFile -Value $mt -NoNewline -Encoding UTF8
    [xml](Get-Content -LiteralPath $miFile -Raw) | Out-Null   # re-validate after the edit
    Write-Host "synced modinfo: tier thresholds + tested-on version ($testedVersion)"
}
$rmFile = Join-Path $modDir 'README.md'
if (Test-Path $rmFile) {
    $rows = ($ages | ForEach-Object { "| $($_.AgeName) | $($_.Pops -join ' | ') |" }) -join $NL
    $tbl = "<!-- GEN:tiers (auto-generated by gen-ascendant.ps1) -->$NL| Age | T1 | T2 | T3 |$NL|---|---:|---:|---:|$NL$rows$NL<!-- /GEN:tiers -->"
    $rt = Get-Content -LiteralPath $rmFile -Raw
    $rt = $rt -replace '(?s)<!-- GEN:tiers.*?<!-- /GEN:tiers -->', $tbl
    $rt = $rt -replace 'Civilization VII \*\*[0-9][0-9.]*\*\*', "Civilization VII **$testedVersion**"
    Set-Content -LiteralPath $rmFile -Value $rt -NoNewline -Encoding UTF8
    Write-Host "synced README: tier table + tested-on version"
}

Write-Host "DONE"
