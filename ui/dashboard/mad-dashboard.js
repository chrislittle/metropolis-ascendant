/**
 * ma-bonus-dashboard — the Metropolis Ascendant bonus dashboard panel.
 *
 * READ-ONLY instrument panel. Answers three questions, in order:
 *   1. Am I still TALL? (vitals strip: total settlements vs the earned allowance, with a SUSPENDED banner when over)
 *   2. What's ON right now? (lit cards, per-lane counts)
 *   3. What turns on NEXT? (grey cards named by their gate tech/civic)
 *
 * Data is discovered from the live DB at runtime — no manifest, no generator coupling:
 *   - GameInfo.ProgressionTreeNodeUnlocks rows with TargetType MA_*_NOTE_* = the card list
 *     (gate node + UnlockDepth 1=base / 2=mastery). Each Age loads only its own rows, so the
 *     catalog auto-scopes to the current Age.
 *   - GameInfo.ModifierStrings (Context "Description") = each card's LOC text — the exact
 *     strings the tech-tree notes show, so the dashboard can never drift from the mod.
 *   - Game.ProgressionTrees.getNode(player, node).depthUnlocked = unlocked state (depth-aware).
 *
 * See DESIGN.md for the full UX story. Draft = Phase 1 (catalog view).
 */
import Panel from '/core/ui/panel-support.js';
import { MustGetElement } from '/core/ui/utilities/utilities-dom.js';
import { InputEngineEventName } from '/core/ui/input/input-support.js';
import NavTray from '/core/ui/navigation-tray/model-navigation-tray.js';
import { FocusManager } from '/core/ui-next/services/focus-manager.js';
import MadSettings from 'fs://game/metropolis-ascendant/ui/options/mad-options.js';

const TAG = '[ma-bonus-dashboard]';

// (The old T1/T2/T3 population-tier ladder was retired with Gen-2 — the Ascendancy tree
// carries all growth scaling now; vitals show the plain Urban Population number.)

// Victory-lane grouping. Token = the part of the note id after "_NOTE_".
const TOKEN_LANE = {
    SCIENCE: 'science', STAGE_SCIENCE: 'science',
    CULTURE: 'culture', STAGE_CULTURE: 'culture', RELIGION: 'culture',
    RESORT: 'arcadia',
    ECONOMIC: 'economy', TRADE: 'economy',
    MILITARY: 'military', FORT: 'military',
    FOODCAP: 'growth', PRODCAP: 'growth',
    SUZERAIN: 'suzerain',
};
// Gen-2 lanes = the Ascendancy tree's own 7 branches, then the static-core sections.
const LANE_ORDER = ['settlements', 'science', 'culture', 'economy', 'military', 'expansion', 'industry', 'diplomacy', 'cards', 'triumphs', 'arcadia', 'foundations', 'surveyor', 'conquest', 'protectorates', 'other'];
const LANE_LOC = {
    science: 'LOC_MAD_LANE_SCIENCE',
    culture: 'LOC_MAD_LANE_CULTURE',
    economy: 'LOC_MAD_LANE_ECONOMY',
    military: 'LOC_MAD_LANE_MILITARY',
    expansion: 'LOC_MAD_LANE_EXPANSION',
    industry: 'LOC_MAD_LANE_INDUSTRY',
    diplomacy: 'LOC_MAD_LANE_DIPLOMACY',
    cards: 'LOC_MAD_LANE_CARDS',
    triumphs: 'LOC_MAD_LANE_TRIUMPHS',
    arcadia: 'LOC_MAD_LANE_ARCADIA',
    foundations: 'LOC_MAD_LANE_FOUNDATIONS',
    surveyor: 'LOC_MAD_LANE_SURVEYOR',
    conquest: 'LOC_MAD_LANE_CONQUEST',
    protectorates: 'LOC_MAD_LANE_PROTECTORATES',
    settlements: 'LOC_MAD_LANE_SETTLEMENTS',
    other: 'LOC_MAD_LANE_OTHER',
};

// Sections that are NOT node-gated (static-world / always-on families). These render as a
// lane intro line; node-gated cards in the same lane (e.g. the Arcadia awakening note on the
// wonder tech's Mastery) list beneath them.
// `state`: 'always' = counts as active; 'nw' = active once a Natural Wonder has been found;
// undefined = informational only (no state, no count).
const STATIC_SECTIONS = {
    arcadia: { gate: 'LOC_MAD_ARCADIA_GATE', body: 'LOC_MAD_ARCADIA_BODY', state: 'nw', activeText: 'LOC_MAD_ARCADIA_AWAKENED' },
    foundations: { gate: 'LOC_MAD_FOUNDATIONS_GATE', body: 'LOC_MAD_FOUNDATIONS_BODY', state: 'always' },
    surveyor: { gate: 'LOC_MAD_SURV_GATE', body: 'LOC_MAD_SURV_BODY' },
    conquest: { gate: 'LOC_MAD_CONQUEST_GATE', body: 'LOC_MAD_CONQUEST_BODY', state: 'kit', activeText: 'LOC_MAD_CONQUEST_ACTIVE' },
    protectorates: { gate: 'LOC_MAD_PROTECTORATES_GATE', body: 'LOC_MAD_PROTECTORATES_BODY', state: 'suz', activeText: 'LOC_MAD_PROTECTORATES_ACTIVE' },
};

/**
 * Surveyor reach counter: resources at hex distance 4-5 from your settlements — beyond the
 * 3-ring workable radius, inside the Surveyor's 5-hex claim range. Only counts plots the
 * player has revealed. City ownership is engine-capped at 3 rings, so any player-owned
 * resource plot out here was Surveyor-claimed.
 */
function surveyorRingStats(playerId) {
    try {
        const player = Players.get(playerId);
        const cities = player?.Cities?.getCities() ?? [];
        if (cities.length == 0) return null;
        const inner = new Set();
        for (const city of cities) {
            const loc = city.location;
            if (!loc) continue;
            for (const idx of GameplayMap.getPlotIndicesInRadius(loc.x, loc.y, 3)) inner.add(idx);
        }
        const hidden = (typeof RevealedStates != 'undefined' && RevealedStates?.HIDDEN != null)
            ? RevealedStates.HIDDEN : 'HIDDEN';
        const noRes = (typeof ResourceTypes != 'undefined' && ResourceTypes?.NO_RESOURCE != null)
            ? ResourceTypes.NO_RESOURCE : -1;
        const seen = new Set();
        let total = 0, claimed = 0;
        for (const city of cities) {
            const loc = city.location;
            if (!loc) continue;
            for (const idx of GameplayMap.getPlotIndicesInRadius(loc.x, loc.y, 5)) {
                if (inner.has(idx) || seen.has(idx)) continue;
                seen.add(idx);
                const l = GameplayMap.getLocationFromIndex(idx);
                if (!l) continue;
                if (GameplayMap.getAreaIsWater?.(l.x, l.y)) continue; // Surveyor can't claim water resources
                const res = GameplayMap.getResourceType(l.x, l.y);
                if (res == null || res == noRes || res == -1) continue;
                const st = GameplayMap.getRevealedState(playerId, l.x, l.y);
                if (st == null || st == hidden || String(st).toUpperCase() == 'HIDDEN') continue;
                total++;
                if (GameplayMap.getOwner(l.x, l.y) == playerId) claimed++;
            }
        }
        return { total, claimed };
    } catch (e) {
        console.error(`${TAG} surveyor ring scan failed: ${e}`);
        return null;
    }
}

// live Age-scaled payout numbers for the conquest kit, read from the modifiers' own args
function modArg(modifierId, name) {
    try {
        const row = GameInfo.ModifierArguments.find(a => a.ModifierId == modifierId && a.Name == name);
        if (!row) return null;
        const n = Number(row.Value);
        return Number.isFinite(n) ? n : row.Value;
    } catch (e) { return null; }
}

function conquestPayoutLines() {
    const sfx = currentAgeSfx();
    const lines = [];
    const capGold = modArg(`MA_${sfx}_RAZE_CAPTURE_GOLD`, 'Amount');
    const capInf = modArg(`MA_${sfx}_RAZE_CAPTURE_DIPLOMACY`, 'Amount');
    if (capGold != null || capInf != null) {
        const parts = [];
        if (capGold != null) parts.push(`+${capGold} [icon:YIELD_GOLD] Gold`);
        if (capInf != null) parts.push(`+${capInf} [icon:YIELD_DIPLOMACY] Influence`);
        lines.push(`${Locale.compose('LOC_MAD_PAYOUT_CAPTURE')} ${parts.join(' + ')} ${Locale.compose('LOC_MAD_PAYOUT_ONETIME')}`);
    }
    const plGold = modArg(`MA_${sfx}_RAZE_PILLAGE_PLUNDER_GOLD`, 'Amount');
    const plSci = modArg(`MA_${sfx}_RAZE_PILLAGE_PLUNDER_SCIENCE`, 'Amount');
    if (plGold != null || plSci != null) {
        const parts = [];
        if (plGold != null) parts.push(`+${plGold} [icon:YIELD_GOLD] Gold`);
        if (plSci != null) parts.push(`+${plSci} [icon:YIELD_SCIENCE] Science`);
        lines.push(`${Locale.compose('LOC_MAD_PAYOUT_PILLAGE')} ${parts.join(' / ')} ${Locale.compose('LOC_MAD_PAYOUT_PER_BUILDING')}`);
    }
    if (modArg(`MA_${sfx}_RAZE_RATE`, 'Amount') != null) {
        lines.push(Locale.compose('LOC_MAD_PAYOUT_RAZE'));
    }
    return lines;
}

/**
 * Has the local player found a Natural Wonder yet? Map scan for any NW plot whose revealed
 * state isn't hidden. NOTE: this is the REVEAL proxy for the gameplay side's DISCOVERY gate —
 * they can differ at the margin (a turn-1 sighting at the edge of vision reveals without
 * discovering), but for the dashboard's awakening line it's the best queryable signal.
 * Returns true/false, or null when the API read fails (rendered as the gate text).
 */
function anyNaturalWonderFound(playerId) {
    try {
        const w = GameplayMap.getGridWidth();
        const h = GameplayMap.getGridHeight();
        const hidden = (typeof RevealedStates != 'undefined' && RevealedStates?.HIDDEN != null)
            ? RevealedStates.HIDDEN : 'HIDDEN';
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                if (!GameplayMap.isNaturalWonder(x, y)) continue;
                const st = GameplayMap.getRevealedState(playerId, x, y);
                if (st != null && st != hidden && String(st).toUpperCase() != 'HIDDEN') return true;
            }
        }
        return false;
    } catch (e) {
        console.error(`${TAG} natural-wonder scan failed: ${e}`);
        return null;
    }
}

// Arcadia's real gate is DISCOVERED >= 30% of the map's Natural Wonders (not "found any").
// Count distinct NWs by feature type (multi-tile NWs would otherwise over-count); reveal is the
// queryable proxy for discovery. Returns {discovered, total, pct, awakened} or null on read fail.
const ARCADIA_NW_PERCENT = 30; // must match $arcadiaNWPercent in gen-ascendant.ps1
function naturalWonderProgress(playerId) {
    try {
        const w = GameplayMap.getGridWidth(), h = GameplayMap.getGridHeight();
        const hidden = (typeof RevealedStates != 'undefined' && RevealedStates?.HIDDEN != null)
            ? RevealedStates.HIDDEN : 'HIDDEN';
        const totalSet = new Set(), discSet = new Set();
        let tileTotal = 0, tileDisc = 0;
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                if (!GameplayMap.isNaturalWonder(x, y)) continue;
                tileTotal++;
                let feat = null;
                try { feat = GameplayMap.getFeatureType?.(x, y); } catch (e) { /* fall back to tiles */ }
                const st = GameplayMap.getRevealedState(playerId, x, y);
                const revealed = st != null && st != hidden && String(st).toUpperCase() != 'HIDDEN';
                if (revealed) tileDisc++;
                if (feat != null) { totalSet.add(feat); if (revealed) discSet.add(feat); }
            }
        }
        const total = totalSet.size || tileTotal;
        const disc = totalSet.size ? discSet.size : tileDisc;
        const pct = total > 0 ? Math.round(disc / total * 100) : 0;
        return { discovered: disc, total, pct, awakened: pct >= ARCADIA_NW_PERCENT };
    } catch (e) {
        console.error(`${TAG} NW progress scan failed: ${e}`);
        return null;
    }
}

function laneForNoteId(modifierId) {
    const idx = modifierId.indexOf('_NOTE_');
    if (idx < 0) return 'other';
    const token = modifierId.substring(idx + 6).replace(/\d+$/, ''); // "SCIENCE2" -> "SCIENCE"
    return TOKEN_LANE[token] ?? 'other';
}

// Gen-2: map an Ascendancy tree node (NODE_MA_<age>_<suffix><n>) to a victory lane.
// The suffix carries the domain; the render layer is lane-agnostic so this is the only join.
const MA_NODE_LANE = {
    SCI: 'science', CUL: 'culture', ECO: 'economy', MIL: 'military',
    EXP: 'expansion', IND: 'industry', DIP: 'diplomacy',
    BRIDGE: 'economy', REP: 'culture', CHARTER: 'expansion',
};
// Extract the 3-letter domain, tolerating a trailing "B" (mastery-branch node, e.g. SCIB) and rank digits.
function laneForMaNode(nodeType) {
    const m = /^NODE_MA_[A-Z]+_([A-Z]+?)B?\d*$/.exec(String(nodeType));
    return m ? (MA_NODE_LANE[m[1]] ?? 'other') : 'other';
}
// A Mastery (branch) tree is hidden until you earn its same-domain Triumph. Return that
// Triumph's actionable trigger LOC so the Mastery card can tell the player HOW to unlock it.
function revealTriggerFor(nodeType) {
    const m = /^NODE_MA_[A-Z]+_([A-Z]+)B$/.exec(String(nodeType)); // only the branch nodes (SCIB/CULB/…)
    return m ? `LOC_LEGACY_MA_${currentAgeSfx()}_${m[1]}_TRIGGER_DESCRIPTION` : null;
}
// Which (Age, domain) feats actually route a next-Age Dedication — from the deployed
// AdvancedStartCards' UNLOCK_MA_* gates (AQ Expansion, EX Expansion, EX Diplomacy ONLY).
// NOT every feat grants a Dedication; Science/Culture/Economy do not.
const DEDICATION_ROUTES = new Set(['AQ_EXP', 'EX_EXP', 'EX_DIP']);
function masteryRoutesDedication(nodeType) {
    const m = /^NODE_MA_[A-Z]+_([A-Z]+)B$/.exec(String(nodeType));
    return m ? DEDICATION_ROUTES.has(`${currentAgeSfx()}_${m[1]}`) : false;
}
function triumphRoutesDedication(legacyType) {
    const m = /^LEGACY_MA_([A-Z]+)_([A-Z]+)$/.exec(String(legacyType));
    return m ? DEDICATION_ROUTES.has(`${m[1]}_${m[2]}`) : false;
}

// Has the Mastery's reveal Triumph been earned? (= the mastery tree is now open to research.)
// Same read the Triumphs tab uses: Legacies.isTriggered on the same-domain LEGACY_MA_*.
function masteryRevealed(playerId, nodeType) {
    const m = /^NODE_MA_[A-Z]+_([A-Z]+)B$/.exec(String(nodeType));
    if (!m) return false;
    try {
        const comp = Players.get(playerId)?.Legacies;
        const row = GameInfo.Legacies?.find(l => l.LegacyType == `LEGACY_MA_${currentAgeSfx()}_${m[1]}`);
        return legacyTriggered(comp, row) === true;
    } catch (e) { return false; }
}

function noteDescription(modifierId) {
    try {
        const row = GameInfo.ModifierStrings.find(s => s.ModifierId == modifierId && s.Context == 'Description');
        return row?.Text ?? null;
    } catch (e) {
        console.error(`${TAG} ModifierStrings lookup failed for ${modifierId}: ${e}`);
        return null;
    }
}

function nodeInfoFor(nodeType) {
    try {
        return GameInfo.ProgressionTreeNodes.find(n => n.ProgressionTreeNodeType == nodeType) ?? null;
    } catch (e) {
        return null;
    }
}

/**
 * Depth the local player has unlocked on a node (0 = not researched, 1 = base, 2 = mastery).
 * Returns null when the live read fails (rendered as "state unknown", counted as locked).
 * NOTE (first FireTuner check): whether getNode wants the row's $hash, $index or the string id
 * is the one unverified call shape — we try each.
 */
function unlockedDepthFor(nodeRow, playerId) {
    if (!nodeRow) return null;
    const candidates = [nodeRow.$hash, nodeRow.$index, nodeRow.ProgressionTreeNodeType];
    for (const key of candidates) {
        if (key === undefined || key === null) continue;
        try {
            const live = Game.ProgressionTrees.getNode(playerId, key);
            if (live && typeof live.depthUnlocked == 'number') return live.depthUnlocked;
        } catch (e) { /* try the next shape */ }
    }
    return null;
}

// TRIUMPHS: our feats are Legacies (LEGACY_MA_<age>_<domain>). p.Legacies.isTriggered(key)
// = earned?, getProgress(key) = progress. Arg shape unverified → try $hash/$index/string like
// unlockedDepthFor does for getNode. (Probe 2026-07-13 confirmed the Legacies component + methods.)
function legacyTriggered(comp, row) {
    if (!comp?.isTriggered || !row) return null;
    for (const key of [row.$hash, row.$index, row.LegacyType]) {
        if (key == null) continue;
        try { const v = comp.isTriggered(key); if (typeof v == 'boolean') return v; } catch (e) { /* next */ }
    }
    try {
        if (typeof Database != 'undefined' && Database.makeHash)
            return comp.isTriggered(Database.makeHash(row.LegacyType));
    } catch (e) { /* give up */ }
    return null;
}
function legacyProgress(comp, row) {
    if (!comp?.getProgress || !row) return null;
    for (const key of [row.$hash, row.$index, row.LegacyType]) {
        if (key == null) continue;
        try { const v = comp.getProgress(key); if (v != null) return v; } catch (e) { /* next */ }
    }
    return null;
}

// BOOST: a node's deed is done (40% pre-filled) when the run-once marker property is set —
// same marker the boost-glow reads. Player property MA_BOOST_<nodeType> == 1.
function nodeBoosted(playerId, nodeType) {
    try {
        const p = Players.get(playerId);
        if (!p?.getProperty || typeof Database == 'undefined' || !Database.makeHash) return false;
        return Number(p.getProperty(Database.makeHash('MA_BOOST_' + nodeType))) >= 1;
    } catch (e) { return false; }
}

// TREE PROGRESS: per-branch completion of the main Ascendancy tree (for the branch bars).
// Counts nodes with depthUnlocked >= 1 vs total, grouped by the 7 branch lanes.
function collectTreeProgress(playerId) {
    const byLane = {}; let done = 0, total = 0;
    try {
        const tree = `TREE_MA_ASCENDANCY_${currentAgeSfx()}`;
        for (const n of GameInfo.ProgressionTreeNodes) {
            if (n.ProgressionTree != tree) continue;
            const lane = laneForMaNode(n.ProgressionTreeNodeType);
            const d = unlockedDepthFor(n, playerId) ?? 0;   // 0 none · 1 researched · 2 mastery
            const g = (byLane[lane] ??= { segs: [], done: 0, total: 0, mastery: false });
            g.segs.push(d); g.total++; total++;
            if (d >= 1) { g.done++; done++; }
            if (d >= 2) g.mastery = true;
        }
    } catch (e) { console.error(`${TAG} tree progress failed: ${e}`); }
    return { byLane, done, total };
}

// TRADE ROUTES: the engine exposes no player-level TOTAL capacity (getTradeCapacityFromPlayer is
// per-partner; probe 2026-07-13 confirmed no Stats/property total). So we show active routes +
// how many more are startable right now — the headroom the base UI also hides.
function tradeReadout(playerId) {
    try {
        const t = Players.get(playerId)?.Trade;
        if (!t) return null;
        let active = 0, avail = 0;
        try { active = Number(t.countPlayerTradeRoutes?.() ?? 0) || 0; } catch (e) { /* 0 */ }
        try { avail = (t.projectPossibleTradeRoutes?.() ?? []).length; } catch (e) { /* 0 */ }
        return { active, avail };
    } catch (e) { return null; }
}

const AGE_SFX = { AGE_ANTIQUITY: 'AQ', AGE_EXPLORATION: 'EX', AGE_MODERN: 'MO' };
function currentAgeSfx() {
    try {
        for (const [ageType, sfx] of Object.entries(AGE_SFX)) {
            if (Game.age == Game.getHash(ageType)) return sfx;
        }
    } catch (e) { /* fall through */ }
    return 'AQ';
}

// ------------------------------------------------------------------ impact
// MA labels its yield modifiers with Tooltip args; the engine attributes each
// contribution as a tree leaf whose desc = the COMPOSED Tooltip text. We compose
// every known MA label once and bucket-sum matching leaves per yield.
// (player.Stats.getYields() shape: walk `steps` + object-valued base/modifier only.)
const MA_LABEL_KEYS = [
    // shared description labels (bucket id = the LOC key)
    'LOC_MA_TIER1_DESCRIPTION', 'LOC_MA_TIER2_DESCRIPTION', 'LOC_MA_TIER3_DESCRIPTION',
    'LOC_MA_STAGE_DESCRIPTION', 'LOC_MA_UNDERCAP_DESCRIPTION', 'LOC_MA_RESEED_DESCRIPTION',
    'LOC_MA_ARCADIA_DESCRIPTION', 'LOC_MA_ARCADIA_PEAKS_DESCRIPTION', 'LOC_MA_ARCADIA_WATERS_DESCRIPTION',
    // short attribution labels (2026-07-12) — the Arcadia modifiers' Tooltips moved to these
    // one-liners; keep the old _DESCRIPTION keys above for saves that snapshotted the essays.
    'LOC_MA_ARCADIA_LABEL', 'LOC_MA_ARCADIA_PEAKS_LABEL', 'LOC_MA_ARCADIA_WATERS_LABEL',
];
// per-age note-key labels — these are the CARDS' own note keys, so they join to cards directly
const MA_NOTE_LABEL_TOKENS = ['SUZERAIN', 'FOODCAP', 'PRODCAP', 'TRADE', 'FORT', 'RESORT', 'RELIGION'];

function collectImpact() {
    const impact = { buckets: {}, total: {} };   // buckets[key][yieldType] = n; total[yieldType] = n
    try {
        const sfx = currentAgeSfx();
        const labelToKey = new Map();
        for (const key of MA_LABEL_KEYS) labelToKey.set(Locale.compose(key), key);
        for (const tok of MA_NOTE_LABEL_TOKENS) {
            const key = `LOC_MA_${sfx}_NOTE_${tok}`;
            labelToKey.set(Locale.compose(key), key);
        }
        // NOTE (2026-07-17): a node/tradition NAME-matching pass was tried here to surface the Gen-2
        // Ascendancy yields, but it over-counted (MA science read higher than the player's TOTAL) and
        // was reverted. Root cause under investigation: EFFECT_CITY_ADJUST_YIELD_PER_POPULATION does NOT
        // honor the Tooltip arg — those per-pop yields land in the game's "Other" bucket with no label,
        // so they can't be attributed by description at all. A correct live-figures pass for Gen-2 likely
        // has to COMPUTE the per-pop yields from node state, not read the engine's attribution tree.
        const player = Players.get(GameContext.localPlayerID);
        const yields = player?.Stats?.getYields?.();
        if (!yields) return impact;
        for (let i = 0; i < GameInfo.Yields.length; i++) {
            const yieldType = GameInfo.Yields[i].YieldType;
            const root = yields[i];
            let guard = 0;
            const walk = (n, d) => {
                if (!n || typeof n != 'object' || d > 24 || guard++ > 4000) return;
                const kids = (n.steps || []).concat([n.base, n.modifier].filter(x => x && typeof x == 'object'));
                if (kids.length == 0) {
                    if (n.value && n.description && labelToKey.has(n.description)) {
                        const key = labelToKey.get(n.description);
                        (impact.buckets[key] ??= {})[yieldType] = (impact.buckets[key][yieldType] ?? 0) + n.value;
                        impact.total[yieldType] = (impact.total[yieldType] ?? 0) + n.value;
                    }
                    return;
                }
                kids.forEach(k => walk(k, d + 1));
            };
            walk(root, 0);
        }
    } catch (e) {
        console.error(`${TAG} impact walk failed: ${e}`);
    }
    return impact;
}

// Gen-2 live figures (2026-07-18): COMPUTED via Leonardfactory's lf-policies-yields-preview public
// API (optional integration; his mod is MIT). The engine-attribution route cannot see the per-pop
// bulk (EFFECT_CITY_ADJUST_YIELD_PER_POPULATION ignores the Tooltip arg -> lands in "Other"), so we
// compute instead: each MA bonus's modifier ids (generated manifest mad-preview-ids.js) go through
// previewModifierByIds, which evaluates our gate windows against live state (FireTuner-proven
// 2026-07-18: W1+W2 together returned the active-window value only; unresearched nodes preview to 0).
// Called lazily at render -> no load-order dependency; without his mod this returns null and the
// dashboard falls back to the v1-label figures. Values are preview-grade (his engine rounds to ints).
function collectPreviews(cards) {
    const api = globalThis.LfYieldsPreview, man = globalThis.MA_PREVIEW_IDS;
    if (!api?.previewModifierByIds || !man) return null;
    const out = new Map();
    for (const card of cards) {
        for (const key of [card.nodeType, card.tradType]) {
            if (!key || !man[key] || out.has(key)) continue;
            try {
                const r = api.previewModifierByIds(man[key]);
                if (r?.isValid && r.yields && Object.keys(r.yields).length) out.set(key, r.yields);
            } catch (e) { /* previews are a nicety - never break the panel */ }
        }
    }
    return out;
}

// Gen-2 suzerain streams: each City-State TYPE feeds one yield (+1 per 4 Urban Pop); Diplomatic -> Influence.
const SUZ_YIELD = {
    SCIENTIFIC: 'YIELD_SCIENCE', CULTURAL: 'YIELD_CULTURE', MILITARISTIC: 'YIELD_PRODUCTION',
    ECONOMIC: 'YIELD_GOLD', EXPANSIONIST: 'YIELD_FOOD', DIPLOMATIC: 'YIELD_DIPLOMACY',
};
// city-states you lead: any player whose Influence.getSuzerain() names you (majors return
// -1), grouped by city-state type (the diplomacy panel's own read:
// GameInfo.CityStateTypes.lookup(player.getCityStateCityStateType()) → localized Name + enum).
// Returns { total, byType (name->count, back-compat), types ([{name,yield,count}] for the panel) }.
function suzerainCounts(playerId) {
    try {
        const all = Players.getAlive?.() ?? Players.getEverAlive?.() ?? [];
        let total = 0;
        const byType = new Map();     // localized name -> count
        const rows = new Map();       // stable key -> { name, yield, count }
        for (const p of all) {
            try {
                if (p?.Influence?.getSuzerain?.() != playerId) continue;
                total++;
                let typeName = null, enumStr = '';
                try {
                    const t = p.getCityStateCityStateType?.();
                    const row = GameInfo.CityStateTypes.lookup?.(t);
                    if (row?.Name) typeName = Locale.compose(row.Name);
                    enumStr = String(row?.CityStateType ?? t ?? '').toUpperCase();
                } catch (e) { /* type stays unknown */ }
                if (typeName) byType.set(typeName, (byType.get(typeName) ?? 0) + 1);
                let yld = null;
                for (const [k, y] of Object.entries(SUZ_YIELD)) { if (enumStr.includes(k)) { yld = y; break; } }
                const key = enumStr || typeName || 'UNKNOWN';
                const cur = rows.get(key) ?? { name: typeName || key, yield: yld, count: 0 };
                cur.count++;
                rows.set(key, cur);
            } catch (e) { /* skip this player */ }
        }
        return { total, byType, types: [...rows.values()] };
    } catch (e) {
        return null; // unknown — treat as "don't second-guess the card"
    }
}

function formatYieldChips(byYield, round = true) {
    const parts = [];
    for (const [yieldType, v] of Object.entries(byYield)) {
        if (!v) continue;
        const n = round ? Math.round(v * 10) / 10 : v;
        // Pill per pair (Chris 2026-07-18: separators too subtle — make the grouping structural).
        // [STYLE:mad-ychip] -> <span class="mad-ychip"> via Locale.stylize (the proven boost-chip
        // mechanism); rule lives in mad-dashboard.css. Sign-aware: negatives render "-16", not "+-16".
        const s = n < 0 ? `${n}` : `+${n}`;
        parts.push(`[STYLE:mad-ychip]${s} [icon:${yieldType}][/S]`);
    }
    return parts.join(' ');
}

class MadDashboardPanel extends Panel {
    constructor() {
        super(...arguments);
        this.engineInputListener = this.onEngineInput.bind(this);
        this.refreshListener = this.refresh.bind(this);
        // Gen-2: the top control is a SYSTEM switcher, not an all/active/locked filter.
        this.tab = 'tree'; // tree | triumph | card | core | settle
        this.collapsed = new Set(MadSettings.getCollapsedLanes()); // persisted lane collapse
    }

    isLaneCollapsed(laneId) {
        return this.collapsed.has(laneId);
    }

    toggleLane(laneId) {
        if (this.collapsed.has(laneId)) this.collapsed.delete(laneId);
        else this.collapsed.add(laneId);
        MadSettings.setCollapsedLanes([...this.collapsed]);
        this.applyFilter();
    }

    // Expand all / Collapse all — drives the persisted collapsed set for the current tab.
    setAllLanes(expanded) {
        const laneIds = [...this.Root.querySelectorAll('.mad-lane')].map(l => l.dataset.lane);
        if (expanded) this.collapsed.clear();
        else for (const id of laneIds) this.collapsed.add(id);
        MadSettings.setCollapsedLanes([...this.collapsed]);
        this.applyFilter();
    }

    // Gen-2 system tabs.
    // 'branch' (the Institutions tab) REMOVED 2026-07-26: it collected the retired Secret-Branch
    // trees' NODE_MA_*B nodes; the 2026-07-18 fold-in retired those trees, no *B node ships, and
    // the tab sat permanently at 0/0 in every game.
    static TABS = ['tree', 'triumph', 'card', 'core', 'settle'];

    onInitialize() {
        this.frame = MustGetElement('.mad-frame', this.Root);
        this.enableOpenSound = true;
        this.enableCloseSound = true;
    }

    onAttach() {
        this.Root.addEventListener(InputEngineEventName, this.engineInputListener);
        this.frame.addEventListener('subsystem-frame-close', () => { this.close(); });
        // Screen-relative frame (2026-07-26 revision): size from the MEASURED window — not CSS
        // viewport units, which this Coherent build can't be trusted with. ~72% x 85%, clamped:
        // floor = the classic 50x44rem (small screens lose nothing; rem tracks the game's UI
        // scale), cap = 120x80rem (ultrawides don't get a mural). Under the floor width the
        // frame gains .mad-narrow -> the card grid collapses back to one column.
        try {
            const winW = window.innerWidth || document.documentElement.clientWidth || 0;
            const winH = window.innerHeight || document.documentElement.clientHeight || 0;
            const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
            if (winW > 0 && winH > 0) {
                const w = Math.max(50 * rem, Math.min(Math.round(winW * 0.72), 120 * rem));
                const h = Math.max(44 * rem, Math.min(Math.round(winH * 0.85), 80 * rem));
                this.frame.style.width = `${w}px`;
                // FIXED height, not max-height: per-tab content lengths differ, and a
                // shrink-to-fit panel re-centers on every tab switch (the "dashboard jumps
                // around" bug, in-game 2026-07-26). Fixed box + the flexing .mad-scroll
                // interior = the frame never moves; short tabs just show open space.
                this.frame.style.height = `${h}px`;
                this.frame.classList.toggle('mad-narrow', w < 62 * rem);
            }
        } catch (e) { /* fixed CSS size remains the fallback */ }
        this._didInitialCollapse = false; // start every open with all lanes collapsed
        for (const t of MadDashboardPanel.TABS) {
            const btn = this.Root.querySelector(`.mad-tab-${t}`);
            btn?.addEventListener('action-activate', () => this.setTab(t));
        }
        this.Root.querySelector('.mad-expand-all')?.addEventListener('action-activate', () => this.setAllLanes(true));
        this.Root.querySelector('.mad-collapse-all')?.addEventListener('action-activate', () => this.setAllLanes(false));
        // Live refresh on the cheap, verified events; open/close re-reads everything anyway.
        this.Root.listenForEngineEvent?.('CityPopulationChanged', this.refreshListener, this);
        this.Root.listenForEngineEvent?.('ConstructibleAddedToMap', this.refreshListener, this);
        this.Root.listenForEngineEvent?.('NaturalWonderRevealed', this.refreshListener, this);
        this.Root.listenForEngineEvent?.('TechNodeCompleted', this.refreshListener, this);
        this.Root.listenForEngineEvent?.('CultureNodeCompleted', this.refreshListener, this);
        this.refresh();
        try { FocusManager.get().setFocus(this.frame); } catch (e) { /* focus is a nicety */ }
    }

    // Per-civ player-color theming REMOVED 2026-07-26 (Chris: the dashboard reads better in the
    // fixed MA gold palette, and one look for every civ beats a per-leader repaint). The old
    // realizePlayerColors()/applyPlayerAccents() pair painted "active" elements in the leader's
    // engine-derived accent as inline styles (CSS var() theming is dead in this Coherent build).
    // Base CSS colors are now the ONLY paint. See the export repo history for the old system.

    onDetach() {
        this.Root.removeEventListener(InputEngineEventName, this.engineInputListener);
    }

    onReceiveFocus() {
        super.onReceiveFocus();
        NavTray.clear();
        NavTray.addOrUpdateGenericBack();
    }

    onEngineInput(inputEvent) {
        if (inputEvent.detail.status != InputActionStatuses.FINISH) return;
        if (inputEvent.isCancelInput() || inputEvent.detail.name == 'sys-menu') {
            this.close();
            inputEvent.stopPropagation();
            inputEvent.preventDefault();
        }
    }

    setTab(t) {
        const changed = this.tab != t;
        this.tab = t;
        for (const name of MadDashboardPanel.TABS) {
            this.Root.querySelector(`.mad-tab-${name}`)?.classList.toggle('mad-tab-on', name == t);
        }
        this.applyFilter();
        if (changed) {
            try { this.Root.querySelector('fxs-scrollable')?.component?.scrollToPercentage?.(0); }
            catch (e) { /* scroll reset is a nicety */ }
        }
    }

    // JS-driven filtering: hide non-matching cards AND static intros, hide any lane left
    // with nothing matching (a fully-unlocked game shows an EMPTY Locked view), and honor
    // collapsed lanes (header + pill stay, content hides).
    // JS-driven view: show only the ACTIVE system tab's content. Cards carry data-system
    // (tree/branch/card/triumph); the static Core sections show under the 'core' tab. Lit vs
    // grey stays a per-item state (the dot), no longer the primary control.
    applyFilter() {
        const tab = this.tab;
        const activeWord = Locale.compose('LOC_MAD_ACTIVE_WORD');
        let anyLaneVisible = false, totalVis = 0, totalAct = 0;
        for (const lane of this.Root.querySelectorAll('.mad-lane')) {
            const laneId = lane.dataset.lane;
            const isCollapsed = this.isLaneCollapsed(laneId);
            const chevron = lane.querySelector('.mad-chevron');
            if (chevron) chevron.textContent = isCollapsed ? '+' : '−';
            let vis = 0, act = 0;
            for (const card of lane.querySelectorAll('.mad-card')) {
                const match = card.dataset.system == tab;
                if (match) { vis++; if (card.classList.contains('mad-active')) act++; }
                card.style.display = (match && !isCollapsed) ? '' : 'none';
            }
            for (const intro of lane.querySelectorAll('.mad-static')) {
                const match = tab == 'core'; // static-world sections live in the Core tab
                if (match) { vis++; if (intro.dataset.madState == 'on') act++; }
                intro.style.display = (match && !isCollapsed) ? '' : 'none';
            }
            // per-tab pill count — fixes "0/4 active" showing when only 1 of the lane's cards
            // belongs to the active tab (the lane is shared by the Ascendancy + Masteries tabs).
            const pill = lane.querySelector('.mad-lane-pill');
            if (pill) {
                if (vis > 0) { pill.textContent = `${act}/${vis} ${activeWord}`; pill.style.display = ''; }
                else pill.style.display = 'none';
            }
            lane.style.display = vis > 0 ? '' : 'none';
            if (vis > 0) { anyLaneVisible = true; totalVis += vis; totalAct += act; }
        }
        const counts = this.Root.querySelector('.mad-counts');
        if (counts) counts.textContent = `${totalAct}/${totalVis} ${activeWord}`;
        const emptyEl = this.Root.querySelector('.mad-locked-empty');
        if (emptyEl) {
            emptyEl.style.display = !anyLaneVisible ? '' : 'none';
            // Per-tab empty text (2026-07-26): the Cards tab shows what's SLOTTED, so an empty
            // tab means "nothing slotted yet" — the shared "nothing left to unlock" line was a
            // lie there (and dressed the removed Institutions tab's corpse the same way).
            if (!anyLaneVisible) {
                emptyEl.innerHTML = Locale.stylize(this.tab == 'card' ? 'LOC_MAD_CARDS_EMPTY' : 'LOC_MAD_ROUTE_DONE');
            }
        }
    }

    // ---------------------------------------------------------------- data

    collectCards(playerId) {
        // card key: gate node + lane + required depth -> one card with stacked note lines
        const cards = new Map();
        let rows = [];
        try {
            // Gen-2: the Ascendancy tree carries its own notes — MA_ASC_<age>_<node>_NOTE
            // (base, UnlockDepth 1) and _NOTEM (mastery, UnlockDepth 2), attached to the
            // NODE_MA_* nodes. (The old v1 base-tree MA_*_NOTE_* labels are being de-layered.)
            rows = GameInfo.ProgressionTreeNodeUnlocks.filter(u =>
                u.TargetKind == 'KIND_MODIFIER' &&
                typeof u.TargetType == 'string' &&
                u.TargetType.startsWith('MA_ASC_') &&
                (u.TargetType.endsWith('_NOTE') || u.TargetType.endsWith('_NOTEM')) &&
                !u.Hidden);
        } catch (e) {
            console.error(`${TAG} ProgressionTreeNodeUnlocks read failed: ${e}`);
        }
        for (const u of rows) {
            const lane = laneForMaNode(u.ProgressionTreeNodeType);
            const depth = u.UnlockDepth ?? 1;
            const key = `${u.ProgressionTreeNodeType}|${lane}|${depth}`;
            let card = cards.get(key);
            if (!card) {
                const nodeRow = nodeInfoFor(u.ProgressionTreeNodeType);
                const unlockedDepth = unlockedDepthFor(nodeRow, playerId);
                card = {
                    lane,
                    // Every Ascendancy node is the main tree. (The old Secret-Branch "*B" nodes —
                    // the Institutions tab — were retired with the 2026-07-18 fold-in; none ship.)
                    system: 'tree',
                    revealTrigger: revealTriggerFor(u.ProgressionTreeNodeType), // Masteries: how to unlock
                    revealed: masteryRevealed(playerId, u.ProgressionTreeNodeType), // Triumph earned = tree open
                    routesDedication: masteryRoutesDedication(u.ProgressionTreeNodeType), // unlocks a Dedication?
                    nodeType: u.ProgressionTreeNodeType,
                    nodeName: nodeRow?.Name ?? u.ProgressionTreeNodeType,
                    isCivic: String(u.ProgressionTreeNodeType).includes('_CIVIC_'),
                    requiredDepth: depth,
                    unlockedDepth,           // null = unknown
                    cost: Number(nodeRow?.Cost ?? 0) || 0, // research cost ≈ how early the node sits
                    lines: [],
                };
                cards.set(key, card);
            }
            const desc = noteDescription(u.TargetType);
            if (desc) card.lines.push(desc);
        }
        // the Suzerain (DIP-lane) cards' payout needs an actual suzerained city-state on top
        // of the node — mark DORMANT (unlocked but not paying) when you lead none
        const suz = suzerainCounts(playerId);
        for (const card of cards.values()) {
            if (card.lane == 'suzerain') {
                card.suzCount = suz?.total ?? null;
                card.suzByType = suz?.byType ?? null;
                card.dormant = (suz?.total === 0) &&
                    card.unlockedDepth != null && card.unlockedDepth >= card.requiredDepth;
            }
        }
        return [...cards.values()].filter(c => c.lines.length > 0);
    }

    // CARDS tab: the player's active Traditions / Policies / Crises, read live from Culture.
    // getActiveTraditions(slot) is the base game's own read (base-standard/ui/policies/model-
    // policies.js). Return shape is resolved defensively (hash or type row). NEEDS in-game verify.
    collectTraditions(playerId) {
        const out = [];
        try {
            const culture = Players.get(playerId)?.Culture;
            if (!culture?.getActiveTraditions || typeof CultureSlotTypes == 'undefined') return out;
            const SLOTS = [
                ['LOC_MAD_CARD_TRADITION', CultureSlotTypes.TRADITION_CULTURE_SLOT],
                ['LOC_MAD_CARD_POLICY', CultureSlotTypes.POLICY_CULTURE_SLOT],
                ['LOC_MAD_CARD_CRISIS', CultureSlotTypes.CRISIS_CULTURE_SLOT],
            ];
            for (const [kindLoc, slot] of SLOTS) {
                if (slot == null) continue;
                let list = [];
                try { list = culture.getActiveTraditions(slot) ?? []; } catch (e) { continue; }
                for (const t of list) {
                    if (t == null) continue;
                    let row = null;
                    try {
                        row = GameInfo.Traditions?.lookup ? GameInfo.Traditions.lookup(t)
                            : GameInfo.Traditions?.find(x => x.$hash == t || x.TraditionType == t);
                    } catch (e) { /* name falls back below */ }
                    const nm = row?.Name ?? String(t);
                    out.push({
                        lane: 'cards', system: 'card', nodeType: String(t), nodeName: nm,
                        tradType: row?.TraditionType ?? null,   // string key for the yield-preview manifest
                        isCivic: false, requiredDepth: 1, unlockedDepth: 1, kindLoc,
                        lines: [row?.Description ?? nm],
                    });
                }
            }
        } catch (e) { console.error(`${TAG} traditions read failed: ${e}`); }
        return out;
    }

    // TRIUMPHS tab: our feats are Legacies (LEGACY_MA_<age>_<domain>), read live via the player's
    // Legacies component. Scoped to the current Age. Falls back to the placeholder if nothing reads.
    collectTriumphs(playerId) {
        const out = [];
        try {
            const comp = Players.get(playerId)?.Legacies;
            if (!comp) return out;
            let rows = [];
            try {
                rows = GameInfo.Legacies.filter(l =>
                    typeof l.LegacyType == 'string' && l.LegacyType.startsWith('LEGACY_MA_'));
            } catch (e) { return out; }
            let ageHash = null; try { ageHash = Game.age; } catch (e) { /* no age scope */ }
            for (const r of rows) {
                if (ageHash != null && r.Age) { try { if (Game.getHash(r.Age) != ageHash) continue; } catch (e) { /* keep */ } }
                const earned = legacyTriggered(comp, r);
                out.push({
                    lane: 'triumphs', system: 'triumph', nodeType: r.LegacyType,
                    nodeName: r.Name ?? r.LegacyType, isCivic: false, requiredDepth: 1,
                    unlockedDepth: earned === true ? 1 : (earned === false ? 0 : null),
                    progress: legacyProgress(comp, r), kindLoc: 'LOC_MAD_TAB_TRIUMPH',
                    routesDedication: triumphRoutesDedication(r.LegacyType),
                    lines: [r.Description ?? r.TriggerDescription ?? r.LegacyType],
                });
            }
        } catch (e) { console.error(`${TAG} triumphs read failed: ${e}`); }
        return out;
    }

    // Fallback card when the Triumph read yields nothing (kept as a safety net).
    triumphPlaceholder() {
        return {
            lane: 'triumphs', system: 'triumph', nodeType: 'MA_TRIUMPHS',
            nodeName: 'LOC_MAD_TRIUMPH_PENDING_TITLE', isCivic: false,
            requiredDepth: 1, unlockedDepth: null, lines: ['LOC_MAD_TRIUMPH_PENDING_BODY'],
        };
    }

    // SETTLEMENTS tab: one card per settlement source — what it is, HOW to unlock it, and whether
    // you have it. (1) founding settlements (always); (2) & (3) the two Charters, which live in a
    // hidden Charters tree REVEALED by this Age's Expansion Triumph, then researched (+1 each).
    collectSettlements(playerId, vitals) {
        const out = [];
        const sfx = currentAgeSfx();
        const base = (sfx === 'AQ') ? 1 : 2; // free floor this Age (AQ 1 / EX 2 / MO 2)
        // (1) founding settlements — always yours
        out.push({
            lane: 'settlements', system: 'settle', nodeType: 'SETTLE_BASE', kindLoc: 'LOC_MAD_TAB_SETTLE',
            nodeName: 'LOC_MAD_SETTLE_BASE_NAME', requiredDepth: 1, unlockedDepth: 1,
            lines: [Locale.compose('LOC_MAD_SETTLE_BASE_BODY', base)],
        });
        // this Age's Expansion Triumph (the key that reveals the Charters tree)
        let expName = 'LOC_MAD_LANE_EXPANSION', expTrigger = null, expEarned = null;
        try {
            const row = GameInfo.Legacies?.find(l => l.LegacyType == `LEGACY_MA_${sfx}_EXP`);
            if (row) {
                expName = row.Name ?? expName;
                expTrigger = row.TriggerDescription ?? null;
                const comp = Players.get(playerId)?.Legacies;
                expEarned = comp ? legacyTriggered(comp, row) : null; // true / false / null(unknown)
            }
        } catch (e) { /* fall back to generic wording */ }
        // (2) the earned slot - FOLD-IN (2026-07-18): the Charters tree is gone; the Expansion feat
        // grants the slot DIRECTLY, so "have" = the Triumph itself. No research step to advertise.
        {
            const have = expEarned === true;
            const how = have
                ? Locale.compose('LOC_MAD_SETTLE_CHARTER_HAVE')
                : Locale.compose('LOC_MAD_SETTLE_CHARTER_LOCKED',
                    Locale.compose(expName), expTrigger ? Locale.compose(expTrigger) : Locale.compose('LOC_MAD_SETTLE_TRIGGER_TBD'));
            out.push({
                lane: 'settlements', system: 'settle', nodeType: 'SETTLE_CHARTER1', kindLoc: 'LOC_MAD_TAB_SETTLE',
                nodeName: `LOC_NODE_MA_${sfx}_CHARTER1_NAME`, requiredDepth: 1, unlockedDepth: have ? 1 : 0,
                lines: [how],
            });
        }
        return out;
    }

    collectVitals() {
        const vitals = {
            homeland: 0, distant: 0, tall: true, settlements: 0, allowance: 1, charters: 0, ageMaxSettlements: 4,
            urbanPop: 0, happiness: null, stageLoc: null, stageIcon: null,
        };
        try {
            const player = Players.get(GameContext.localPlayerID);
            const cities = player?.Cities?.getCities() ?? [];
            let metropolis = null;
            for (const city of cities) {
                if (city.isDistantLands) vitals.distant++; else vitals.homeland++;
                const urban = city.urbanPopulation ?? 0;
                // Gen-2 (fixed 2026-07-22): SUM across all settlements - the per-pop bonuses pay on
                // empire-wide Urban Population, so the vitals show that number (the old v1 read kept
                // only the single largest city and understated it - 25 shown vs 77 real, run 5).
                vitals.urbanPop += urban;
                // The happiness/stage line still reads the LARGEST city (the metropolis).
                if (!city.isTown && (metropolis == null || urban >= (metropolis.urbanPopulation ?? 0))) {
                    metropolis = city;
                }
            }
            if (metropolis) {
                vitals.happiness = metropolis.Happiness?.netHappinessPerTurn ?? null;
                // happiness STAGE: range-match the city happiness yield against
                // GameInfo.HappinessStages — the base city-banner recipe (city-banners.js)
                const hy = metropolis.Yields?.getYield?.(YieldTypes.YIELD_HAPPINESS);
                if (hy != null) {
                    for (const row of GameInfo.HappinessStages) {
                        const min = row.StageMinThreshold ?? -Infinity;
                        const max = row.StageMaxThreshold ?? Infinity;
                        if (hy >= min && hy <= max) {
                            vitals.stageLoc = row.HappinessStageType.replace('HAPPINESS_STAGE_', 'LOC_UI_CITY_DETAILS_');
                            vitals.stageIcon = row.HappinessStageType.replace('HAPPINESS_STAGE_', 'YIELD_');
                            break;
                        }
                    }
                }
            }
            // Gen-2 THE MA GATE: benefits gate on total settlement count vs the mod's own
            // allowance — base 1 (Antiquity) / 2 (Exploration, Modern), +1 per Charter node
            // completed on the Ascendancy tree, hard-capped at 4. (Replaces the v1 per-
            // hemisphere SOLO rule, which was homeland<=1 && distant<=1.)
            let isAQ = true, isMO = false;
            try { isAQ = (Game.age == Game.getHash('AGE_ANTIQUITY')); } catch (e) { /* default AQ */ }
            try { isMO = (Game.age == Game.getHash('AGE_MODERN')); } catch (e) { /* not MO */ }
            const sfx = currentAgeSfx();
            const pid = GameContext.localPlayerID;
            // FOLD-IN (2026-07-18): slots ride TRIUMPHS now - the Charters tree is gone. Floors AQ 1 /
            // EX 2 / MO 2; this Age's Expansion feat = +1 slot. Max 2/3/4.
            const floor = isAQ ? 1 : 2;
            let allowance = floor;
            let expEarnedNow = false;
            try {
                const rowNow = GameInfo.Legacies?.find(l => l.LegacyType == `LEGACY_MA_${sfx}_EXP`);
                const compNow = Players.get(pid)?.Legacies;
                expEarnedNow = (rowNow && compNow) ? (legacyTriggered(compNow, rowNow) === true) : false;
            } catch (e) { /* unreadable -> conservative floor */ }
            if (expEarnedNow) { allowance++; vitals.charters++; }
            if (isMO) {
                // THE CARRY (fixed 2026-07-22, run-5 in-game): Triumph records are per-Age, so the old
                // probe for Exploration's Twin Capitals ALWAYS read false here and showed SUSPENDED at
                // a legal 3 (proven live: cards +78 Science on slot while the banner said suspended).
                // The delivery rebuild made the data's Modern 3rd-settlement window count-only (the
                // accepted carry design), so the dashboard mirrors that reality: Modern base = 3,
                // Modern's own Expansion feat opens the 4th.
                allowance++; vitals.charters++;
            }
            const ageMax = isAQ ? 2 : (isMO ? 4 : 3);   // per-Age max: AQ 2 / EX 3 / MO 4
            vitals.allowance = Math.min(allowance, ageMax);
            vitals.ageMaxSettlements = ageMax;
            vitals.settlements = vitals.homeland + vitals.distant;
            vitals.tall = vitals.settlements <= vitals.allowance;
        } catch (e) {
            console.error(`${TAG} vitals read failed: ${e}`);
        }
        return vitals;
    }

    // -------------------------------------------------------------- render

    refresh() {
        const playerId = GameContext.localPlayerID;
        const vitals = this.collectVitals();
        const cards = this.collectCards(playerId);
        cards.push(...this.collectTraditions(playerId)); // Cards tab
        const tri = this.collectTriumphs(playerId);      // Triumphs tab (LEGACY_MA_* via Legacies)
        cards.push(...(tri.length ? tri : [this.triumphPlaceholder()]));
        cards.push(...this.collectSettlements(playerId, vitals)); // Settlements tab (base + the two Charters)
        // engine-attributed MA income (labeled leaves); nothing to show while suspended
        this.impact = vitals.tall ? collectImpact() : { buckets: {}, total: {} };
        // computed Gen-2 income (Ascendancy nodes/branches + active MA traditions) via the optional
        // yields-preview API; folds into the headline total. Tree cards only ever contribute when
        // researched + window-open (his engine gates them), and collectTraditions lists only SLOTTED
        // traditions, so nothing unearned is counted.
        this.preview = vitals.tall ? collectPreviews(cards) : null;
        if (this.preview) {
            for (const y of this.preview.values())
                for (const [yt, v] of Object.entries(y)) this.impact.total[yt] = (this.impact.total[yt] ?? 0) + v;
        }
        // computed influence: the Palace primer — a constructible-routed source the engine can't
        // label (EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD), active only at exactly 1 settlement.
        // (The old Hub-town building bonus was removed in the A2 base-tree de-layer, 2026-07-14.)
        this.primer = 0;      // Palace primer — shown on the Foundations chip
        try {
            const sfx = currentAgeSfx();
            if (vitals.tall && (vitals.homeland + vitals.distant) < 2) {
                this.primer += Number(modArg(`MA_${sfx}_SUZ_PRIMER`, 'Amount') ?? 0) || 0;
            }
        } catch (e) { /* computed chips are a nicety */ }
        if (this.primer) this.impact.total.YIELD_DIPLOMACY = (this.impact.total.YIELD_DIPLOMACY ?? 0) + this.primer;
        this.renderVitals(vitals);
        this.renderProgress(playerId);
        this.renderLanes(cards, vitals);
        // Default to all lanes collapsed on first render of this open (Chris 2026-07-13).
        if (!this._didInitialCollapse) {
            for (const lane of this.Root.querySelectorAll('.mad-lane')) this.collapsed.add(lane.dataset.lane);
            this._didInitialCollapse = true;
        }
        this.setTab(this.tab);
    }

    renderVitals(v) {
        const status = this.Root.querySelector('.mad-status');
        const detail = this.Root.querySelector('.mad-status-detail');
        const pop = this.Root.querySelector('.mad-pop');
        const happy = this.Root.querySelector('.mad-happy');
        if (status) {
            status.innerHTML = Locale.stylize(v.tall ? 'LOC_MAD_STATUS_ACTIVE' : 'LOC_MAD_STATUS_SUSPENDED');
            status.classList.toggle('mad-ok', v.tall);
            status.classList.toggle('mad-bad', !v.tall);
        }
        if (detail) {
            // Gen-2 gate readout: always draw the mod's full ceiling (4 slots) so a 1/1 empire still
            // reads as progress, not a lone line. Green = a settlement you hold · hollow = open slot
            // within your allowance · dashed = locked (needs a Charter to open) · amber ring = a slot
            // a Charter granted. No hemisphere split.
            const MAX_SETTLEMENTS = 4;
            let pips = '';
            for (let i = 0; i < MAX_SETTLEMENTS; i++) {
                const held = i < v.settlements;
                const unlocked = i < v.allowance;
                const isCharter = unlocked && i >= (v.allowance - v.charters);
                const cls = ['mad-set-seg'];
                if (held) cls.push('mad-set-seg-on');
                if (!unlocked) cls.push('mad-set-seg-locked');
                if (isCharter) cls.push('mad-set-seg-charter');
                pips += `<span class="${cls.join(' ')}"></span>`;
            }
            let html = `${Locale.compose('LOC_MAD_SETTLEMENTS')} ${v.settlements}/${v.allowance} <span class="mad-set-track">${pips}</span>`;
            if (!v.tall) html += `  ·  ${Locale.compose('LOC_MAD_SUSPENDED_HINT')}`;
            // The "how to raise the cap" detail lives in the Settlements tab (per-slot: what, how, have?).
            detail.innerHTML = html;
        }
        if (pop) {
            // Gen-2 per-pop yields scale continuously (+1 per 2 Urban Pop) — no v1 T1/T2/T3 thresholds.
            pop.textContent = `${Locale.compose('LOC_MAD_URBAN_POP')} ${v.urbanPop}`;
        }
        if (happy) {
            if (v.happiness == null) {
                happy.innerHTML = '';
            } else {
                let txt = `${Locale.compose('LOC_MAD_HAPPINESS')} ${v.happiness >= 0 ? '+' : ''}${Math.round(v.happiness * 10) / 10}`;
                if (v.stageLoc) txt += `  ·  ${v.stageIcon ? `[icon:${v.stageIcon}] ` : ''}${Locale.compose(v.stageLoc)}`;
                happy.innerHTML = Locale.stylize(txt);
            }
        }
        const arcEl = this.Root.querySelector('.mad-arcadia');
        if (arcEl) {
            const np = naturalWonderProgress(GameContext.localPlayerID);
            arcEl.classList.toggle('mad-arcadia-on', !!(np && np.awakened));
            if (np && np.total > 0) {
                const name = Locale.compose(LANE_LOC['arcadia']);
                arcEl.innerHTML = np.awakened
                    ? Locale.stylize(`${name} — ${Locale.compose('LOC_MAD_ARCADIA_AWAKE_SHORT')}`)
                    : Locale.stylize(`${name} — ${np.discovered}/${np.total} ${Locale.compose('LOC_MAD_NW_THRESHOLD')}`);
            } else {
                arcEl.innerHTML = '';
            }
        }
        const tradeEl = this.Root.querySelector('.mad-trade');
        if (tradeEl) {
            const tr = tradeReadout(GameContext.localPlayerID);
            tradeEl.innerHTML = tr
                ? Locale.stylize(`[icon:YIELD_GOLD] ${Locale.compose('LOC_MAD_TRADE')} ${tr.active} ${Locale.compose('LOC_MAD_TRADE_ACTIVE')} · ${tr.avail} ${Locale.compose('LOC_MAD_TRADE_AVAIL')}`)
                : '';
        }
        const impactEl = this.Root.querySelector('.mad-impact');
        if (impactEl) {
            // Headline figures require the yields-preview API (Chris 2026-07-18): without it the total
            // would degrade to the v1-label remnant (basically the happiness line) and READ as broken.
            // No figures beats partial figures - skip the line entirely when the API is absent.
            const chips = (MadSettings.showFigures && this.preview) ? formatYieldChips(this.impact?.total ?? {}) : '';
            impactEl.innerHTML = chips
                ? Locale.stylize(`${Locale.compose('LOC_MAD_IMPACT_NOW')}  ${chips} ${Locale.compose('LOC_MAD_PER_TURN')}`)
                : '';
        }
        this.frame.classList.toggle('mad-suspended', !v.tall);
    }

    // Per-branch segmented progress bars for the main Ascendancy tree (Chris's "branch bars").
    renderProgress(playerId) {
        // 2026-07-26 revision: LANE CHIPS replace the segmented bars — at 1-3 nodes per lane a
        // bar is just a rectangle. One centered row of pills; THE CHIP IS THE PROGRESS BAR
        // (proportional gold fill, the same rule as the tree-tooltip cost pill): dim = untouched,
        // gold border + partial fill = in progress, solid gold = lane complete. The count keeps
        // the mastery star.
        const host = this.Root.querySelector('.mad-progress');
        if (!host) return;
        host.innerHTML = '';
        const prog = collectTreeProgress(playerId);
        if (!prog.total) return;
        const row = document.createElement('div');
        row.classList.add('mad-lchip-row');
        for (const lane of ['science', 'culture', 'economy', 'military', 'expansion', 'industry', 'diplomacy']) {
            const b = prog.byLane[lane];
            if (!b || !b.total) continue;
            const chip = document.createElement('span');
            chip.classList.add('mad-lchip');
            const pct = Math.max(0, Math.min(100, Math.round(b.done / b.total * 100)));
            if (pct >= 100) chip.classList.add('mad-lchip-done');
            else if (pct > 0) {
                chip.classList.add('mad-lchip-part');
                const fill = document.createElement('span');
                fill.classList.add('mad-lchip-fill');
                fill.style.width = `${pct}%`;
                chip.appendChild(fill);
            }
            const t = document.createElement('span');
            t.classList.add('mad-lchip-t');
            const cnt = `<span class="mad-lchip-cnt">${b.done}/${b.total}${b.mastery ? ' ★' : ''}</span>`;
            t.innerHTML = `${Locale.compose(LANE_LOC[lane])} ${cnt}`;
            chip.appendChild(t);
            row.appendChild(chip);
        }
        host.appendChild(row);
    }

    renderLanes(cards, vitals) {
        const host = this.Root.querySelector('.mad-lanes');
        if (!host) return;
        host.innerHTML = '';

        if (cards.length == 0) {
            const empty = document.createElement('div');
            empty.classList.add('mad-empty');
            empty.innerHTML = Locale.stylize('LOC_MAD_NO_MA');
            host.appendChild(empty);
            return;
        }

        const byLane = new Map();
        for (const card of cards) {
            if (!byLane.has(card.lane)) byLane.set(card.lane, []);
            byLane.get(card.lane).push(card);
        }

        const playerId = GameContext.localPlayerID;
        // Arcadia awakens at 30% of NWs discovered — use the real percentage, not "found any".
        const nwProg = naturalWonderProgress(playerId);
        const nwFound = nwProg ? nwProg.awakened : anyNaturalWonderFound(playerId);
        // Protectorates (suzerain) live read — drives the static section's state + breakdown.
        const suz = suzerainCounts(playerId);

        let totalActive = 0, totalCards = 0;
        for (const lane of LANE_ORDER) {
            const laneCards = byLane.get(lane) ?? [];
            const staticDef = STATIC_SECTIONS[lane];
            if (laneCards.length == 0 && !staticDef) continue;

            const section = document.createElement('div');
            section.classList.add('mad-lane');
            section.dataset.lane = lane;

            let active = laneCards.filter(c => !c.dormant && c.unlockedDepth != null && c.unlockedDepth >= c.requiredDepth).length;
            let count = laneCards.length;
            // a stateful static section (Arcadia awakening, Foundations) counts in the pill
            let staticOn = null;
            if (staticDef?.state == 'always') staticOn = true;
            else if (staticDef?.state == 'nw') staticOn = nwFound; // true/false/null(unknown)
            else if (staticDef?.state == 'kit') staticOn = (vitals.homeland + vitals.distant) < 3; // conquest kit: under 3 settlements
            else if (staticDef?.state == 'suz') staticOn = suz ? (suz.total > 0) : null; // protectorates: active once you hold any suzerainty
            if (staticOn != null) { count += 1; if (staticOn) active += 1; }
            totalActive += active;
            totalCards += count;

            const head = document.createElement('div');
            head.classList.add('mad-lane-head');
            const chevron = document.createElement('span');
            chevron.classList.add('mad-chevron');
            chevron.textContent = this.collapsed.has(lane) ? '+' : '−';
            head.appendChild(chevron);
            const title = document.createElement('span');
            title.classList.add('mad-lane-title');
            title.textContent = Locale.compose(LANE_LOC[lane]);
            head.appendChild(title);
            head.addEventListener('click', () => this.toggleLane(lane));
            if (count > 0) {
                const pill = document.createElement('span');
                pill.classList.add('mad-lane-pill');
                const suspended = !vitals.tall;
                pill.classList.toggle('mad-pill-lit', active > 0 && !suspended);
                pill.classList.toggle('mad-pill-paused', active > 0 && suspended);
                let txt = (staticDef?.state == 'always' && laneCards.length == 0)
                    ? Locale.compose('LOC_MAD_ALWAYS_ON')
                    : `${active}/${count} ${Locale.compose('LOC_MAD_ACTIVE_WORD')}`;
                if (active > 0 && suspended) txt += ` ${Locale.compose('LOC_MAD_PAUSED')}`;
                pill.textContent = txt;
                head.appendChild(pill);
            }
            section.appendChild(head);

            if (staticDef) {
                const intro = document.createElement('div');
                intro.classList.add('mad-static');
                intro.dataset.madState = staticOn === true ? 'on' : (staticOn === false ? 'off' : 'info');
                const gate = document.createElement('div');
                gate.classList.add('mad-static-gate');
                if (staticOn === true && staticDef.activeText) {
                    gate.innerHTML = Locale.stylize(staticDef.activeText);
                    gate.classList.add('mad-static-on');
                } else if (staticOn === true) {
                    gate.innerHTML = Locale.stylize(staticDef.gate);
                    gate.classList.add('mad-static-on');
                } else {
                    gate.innerHTML = Locale.stylize(staticDef.gate);
                }
                const body = document.createElement('div');
                body.classList.add('mad-static-body');
                body.innerHTML = Locale.stylize(staticDef.body);
                intro.appendChild(gate);
                intro.appendChild(body);
                // conquest kit: live payout lines for the current Age (from the modifiers' own args)
                if (lane == 'conquest') {
                    for (const line of conquestPayoutLines()) {
                        const row = document.createElement('div');
                        row.classList.add('mad-payout');
                        row.innerHTML = Locale.stylize(line);
                        intro.appendChild(row);
                    }
                }
                // arcadia: live Natural-Wonder discovery count vs the 30% awaken gate
                if (lane == 'arcadia' && nwProg && nwProg.total > 0) {
                    const row = document.createElement('div');
                    row.classList.add('mad-payout');
                    row.textContent = `${Locale.compose('LOC_MAD_NW_DISCOVERED')} ${nwProg.discovered} / ${nwProg.total} · ${nwProg.pct}% ${Locale.compose('LOC_MAD_NW_THRESHOLD')}`;
                    intro.appendChild(row);
                }
                // surveyor: ring 4-5 resource counter
                if (lane == 'surveyor') {
                    const stats = surveyorRingStats(playerId);
                    if (stats) {
                        const row = document.createElement('div');
                        row.classList.add('mad-payout');
                        row.textContent = stats.total > 0
                            ? `${Locale.compose('LOC_MAD_SURV_CLAIMED')} ${stats.claimed} ${Locale.compose('LOC_MAD_SURV_OF')} ${stats.total} ${Locale.compose('LOC_MAD_SURV_TAIL')}`
                            : Locale.compose('LOC_MAD_SURV_NONE');
                        intro.appendChild(row);
                    }
                }
                // protectorates: live breakdown of which City-State types you're Suzerain of + the yield each feeds
                if (lane == 'protectorates' && suz) {
                    const row = document.createElement('div');
                    row.classList.add('mad-payout');
                    if (suz.total > 0 && suz.types.length) {
                        const parts = suz.types
                            .slice().sort((a, b) => b.count - a.count)
                            .map(t => `${t.yield ? `[icon:${t.yield}] ` : ''}${t.name}${t.count > 1 ? ` ×${t.count}` : ''}`);
                        row.innerHTML = Locale.stylize(`${Locale.compose('LOC_MAD_PROT_SUZ_OF')} ${suz.total} — ${parts.join('  ·  ')}`);
                    } else {
                        row.innerHTML = Locale.stylize(Locale.compose('LOC_MAD_PROT_NONE'));
                    }
                    intro.appendChild(row);
                }
                // live engine-attributed chips on the static sections
                let chipTxt = '';
                if (!MadSettings.showFigures) { /* plain catalog view */ }
                else if (lane == 'arcadia') {
                    const merged = {};
                    for (const key of ['LOC_MA_ARCADIA_DESCRIPTION', 'LOC_MA_ARCADIA_PEAKS_DESCRIPTION', 'LOC_MA_ARCADIA_WATERS_DESCRIPTION',
                                       'LOC_MA_ARCADIA_LABEL', 'LOC_MA_ARCADIA_PEAKS_LABEL', 'LOC_MA_ARCADIA_WATERS_LABEL']) {
                        for (const [yt, v] of Object.entries(this.impact?.buckets?.[key] ?? {})) merged[yt] = (merged[yt] ?? 0) + v;
                    }
                    chipTxt = formatYieldChips(merged);
                } else if (lane == 'foundations') {
                    const merged = { ...(this.impact?.buckets?.['LOC_MA_TIER1_DESCRIPTION'] ?? {}) };
                    if (this.primer) merged.YIELD_DIPLOMACY = (merged.YIELD_DIPLOMACY ?? 0) + this.primer;
                    chipTxt = formatYieldChips(merged);
                }
                if (chipTxt) {
                    const chip = document.createElement('div');
                    chip.classList.add('mad-chip');
                    chip.innerHTML = Locale.stylize(`${chipTxt} ${Locale.compose('LOC_MAD_PER_TURN')}`);
                    intro.appendChild(chip);
                }
                section.appendChild(intro);
            }

            // active cards first; within each group, cheapest gate node first ("next up" order)
            const sorted = [...laneCards].sort((a, b) => {
                const activeDiff =
                    Number(b.unlockedDepth != null && b.unlockedDepth >= b.requiredDepth) -
                    Number(a.unlockedDepth != null && a.unlockedDepth >= a.requiredDepth);
                return activeDiff != 0 ? activeDiff : (a.cost - b.cost);
            });
            // 2026-07-26 revision: cards live in a .mad-cards GRID (3-across in the widened
            // frame; single column again under .mad-narrow). applyFilter still finds them —
            // it queries descendants, and display:none removes a card from grid flow cleanly.
            const cardsWrap = document.createElement('div');
            cardsWrap.classList.add('mad-cards');
            for (const card of sorted) cardsWrap.appendChild(this.renderCard(card));
            section.appendChild(cardsWrap);

            host.appendChild(section);
        }

        const counts = this.Root.querySelector('.mad-counts');
        if (counts) counts.textContent = `${totalActive}/${totalCards} ${Locale.compose('LOC_MAD_ACTIVE_WORD')}`;

        const emptyEl = this.Root.querySelector('.mad-locked-empty');
        if (emptyEl) emptyEl.innerHTML = Locale.stylize('LOC_MAD_ROUTE_DONE');
    }

    renderCard(card) {
        const isActive = card.unlockedDepth != null && card.unlockedDepth >= card.requiredDepth;
        const stateUnknown = card.unlockedDepth == null;

        const el = document.createElement('div');
        el.classList.add('mad-card', isActive ? 'mad-active' : 'mad-locked');
        el.dataset.system = card.system ?? 'tree'; // which switcher tab this card belongs to
        if (card.dormant) el.classList.add('mad-dormant');

        const head = document.createElement('div');
        head.classList.add('mad-card-head');
        const dot = document.createElement('span');
        dot.classList.add('mad-dot');
        head.appendChild(dot);
        const name = document.createElement('span');
        name.classList.add('mad-card-title');
        let titleText = Locale.compose(card.nodeName);
        if (card.requiredDepth >= 2) titleText += ` — ${Locale.compose('LOC_MAD_MASTERY')}`;
        name.textContent = titleText;
        head.appendChild(name);
        // explicit spacer: the engine's flexbox ignores margin-left:auto, so this is
        // how the kind tag reaches the right edge
        const spacer = document.createElement('span');
        spacer.classList.add('mad-spacer');
        head.appendChild(spacer);
        const kind = document.createElement('span');
        kind.classList.add('mad-card-kind');
        // Gen-2: tree/branch cards are Ascendancy nodes (not base TECH/CIVIC); cards show their slot.
        const kindKey = card.kindLoc
            ?? (card.system == 'triumph' ? 'LOC_MAD_TAB_TRIUMPH' : 'LOC_MAD_KIND_ASCENDANCY');
        kind.textContent = Locale.compose(kindKey);
        head.appendChild(kind);
        // Boost tag: a not-yet-complete Ascendancy/Mastery node whose deed is done (40% pre-filled).
        if (!isActive && card.system == 'tree'
            && nodeBoosted(GameContext.localPlayerID, card.nodeType)) {
            const boost = document.createElement('span');
            boost.classList.add('mad-boost-tag');
            boost.textContent = Locale.compose('LOC_MAD_BOOSTED');
            head.appendChild(boost);
        }
        // AVAILABLE: Mastery revealed (Triumph earned) but not yet researched — nudge to open its tree.
        if (card.revealed && !isActive) {
            const avail = document.createElement('span');
            avail.classList.add('mad-avail-tag');
            avail.textContent = Locale.compose('LOC_MAD_AVAILABLE');
            head.appendChild(avail);
            el.classList.add('mad-available');
        }
        // Reward-type tag on Triumphs: DEDICATION (a next-Age pick) vs IMMEDIATE (pays now).
        if (card.system == 'triumph') {
            const rew = document.createElement('span');
            rew.classList.add(card.routesDedication ? 'mad-ded-tag' : 'mad-imm-tag');
            rew.textContent = Locale.compose(card.routesDedication ? 'LOC_MAD_TAG_DEDICATION' : 'LOC_MAD_TAG_IMMEDIATE');
            head.appendChild(rew);
        }
        el.appendChild(head);

        const body = document.createElement('div');
        body.classList.add('mad-card-body');
        for (const line of card.lines) {
            const p = document.createElement('div');
            p.classList.add('mad-card-line');
            p.innerHTML = Locale.stylize(line);
            body.appendChild(p);
        }
        el.appendChild(body);

        const foot = document.createElement('div');
        foot.classList.add('mad-card-foot');
        if (card.revealTrigger && !isActive && card.revealed) {
            // Triumph earned → the Mastery tree is OPEN; nudge the player to go research it.
            foot.innerHTML = Locale.stylize(`${Locale.compose('LOC_MAD_MASTERY_READY')} ${Locale.compose(card.nodeName)}`);
        } else if (card.revealTrigger && !isActive) {
            // Still hidden — tell the player which Triumph reveals it and how to earn that.
            foot.innerHTML = Locale.stylize(`${Locale.compose('LOC_MAD_REVEALED_BY')} ${Locale.compose(LANE_LOC[card.lane] ?? 'LOC_MAD_LANE_OTHER')} ${Locale.compose('LOC_MAD_TRIUMPH_WORD')} ${Locale.compose(card.revealTrigger)}`);
        } else if (stateUnknown) {
            foot.textContent = `${Locale.compose(card.nodeName)} · ${Locale.compose('LOC_MAD_STATE_UNKNOWN')}`;
        } else if (card.dormant) {
            foot.textContent = `${Locale.compose('LOC_MAD_UNLOCKED')} · ${Locale.compose('LOC_MAD_SUZ_NONE')}`;
        } else if (isActive) {
            let txt = Locale.compose('LOC_MAD_UNLOCKED');
            if (card.suzCount != null && card.suzCount > 0) {
                txt += ` · ${Locale.compose('LOC_MAD_SUZ_LEAD')} ${card.suzCount} ${Locale.compose(card.suzCount == 1 ? 'LOC_MAD_SUZ_CS_ONE' : 'LOC_MAD_SUZ_CS_MANY')}`;
                if (card.suzByType?.size) {
                    const parts = [...card.suzByType.entries()]
                        .sort((a, b) => b[1] - a[1])
                        .map(([name, n]) => `${name} ${n}`);
                    txt += ` (${parts.join(' · ')})`;
                }
            }
            foot.textContent = txt;
        } else {
            let gate = Locale.compose(card.nodeName);
            if (card.requiredDepth >= 2) gate += ` (${Locale.compose('LOC_MAD_MASTERY')})`;
            foot.textContent = `${Locale.compose('LOC_MAD_LOCKED_AT')} ${gate}`;
        }
        el.appendChild(foot);

        // live engine-attributed impact chip: note-key buckets join to the card's own note
        // keys; stage/under-cap buckets join by yield to their specific note card.
        // Figures are all-or-nothing (Chris 2026-07-18): every number on the dashboard requires the
        // yields-preview API. Without it, no chips anywhere - not even the v1-label ones.
        if (isActive && MadSettings.showFigures && this.preview) {
            const merged = {};
            const add = (byYield, onlyYield = null) => {
                for (const [yt, v] of Object.entries(byYield ?? {})) {
                    if (onlyYield && yt != onlyYield) continue;
                    merged[yt] = (merged[yt] ?? 0) + v;
                }
            };
            const sfx = currentAgeSfx();
            for (const lineKey of card.lines) add(this.impact?.buckets?.[lineKey]);
            // computed Gen-2 chip (yields-preview API); key spaces are disjoint from the v1 label
            // buckets above, so a card never double-counts.
            const pvKey = [card.nodeType, card.tradType].find(k => k && this.preview?.has(k));
            if (pvKey) add(this.preview.get(pvKey));
            if (card.lines.includes(`LOC_MA_${sfx}_NOTE_STAGE_SCIENCE`)) add(this.impact?.buckets?.['LOC_MA_STAGE_DESCRIPTION'], 'YIELD_SCIENCE');
            if (card.lines.includes(`LOC_MA_${sfx}_NOTE_STAGE_CULTURE`)) add(this.impact?.buckets?.['LOC_MA_STAGE_DESCRIPTION'], 'YIELD_CULTURE');
            if (card.lines.includes(`LOC_MA_${sfx}_NOTE_FOODCAP`)) add(this.impact?.buckets?.['LOC_MA_UNDERCAP_DESCRIPTION'], 'YIELD_FOOD');
            if (card.lines.includes(`LOC_MA_${sfx}_NOTE_PRODCAP`)) add(this.impact?.buckets?.['LOC_MA_UNDERCAP_DESCRIPTION'], 'YIELD_PRODUCTION');
            const chipTxt = formatYieldChips(merged);
            if (chipTxt) {
                const chip = document.createElement('div');
                chip.classList.add('mad-chip');
                chip.innerHTML = Locale.stylize(`${chipTxt} ${Locale.compose('LOC_MAD_PER_TURN')}`);
                el.appendChild(chip);
            }
        }

        return el;
    }
}

Controls.define('panel-ma-dashboard', {
    createInstance: MadDashboardPanel,
    description: 'Metropolis Ascendant bonus dashboard.',
    styles: ['fs://game/metropolis-ascendant/ui/dashboard/mad-dashboard.css'],
    content: ['fs://game/metropolis-ascendant/ui/dashboard/mad-dashboard.html'],
    attributes: [],
    classNames: ['mad-root', 'absolute', 'inset-0', 'flex', 'items-center', 'justify-center'],
});
