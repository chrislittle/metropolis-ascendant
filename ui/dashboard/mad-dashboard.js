/**
 * ma-bonus-dashboard — the Metropolis Ascendant bonus dashboard panel.
 *
 * READ-ONLY instrument panel. Answers three questions, in order:
 *   1. Am I still TALL? (vitals strip: settlements per hemisphere vs the 1/hemisphere law)
 *   2. What's ON right now? (lit cards, per-lane counts)
 *   3. What turns on NEXT? (grey cards named by their gate tech/civic; tier bar in the header)
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

// Population tier thresholds per Age (T1/T2/T3) — matches gen-ascendant's tuning.
const AGE_TIERS = {
    AGE_ANTIQUITY: [5, 9, 12],
    AGE_EXPLORATION: [8, 14, 20],
    AGE_MODERN: [10, 16, 24],
};

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
const LANE_ORDER = ['science', 'culture', 'economy', 'military', 'growth', 'suzerain', 'arcadia', 'foundations', 'surveyor', 'conquest', 'other'];
const LANE_LOC = {
    science: 'LOC_MAD_LANE_SCIENCE',
    culture: 'LOC_MAD_LANE_CULTURE',
    economy: 'LOC_MAD_LANE_ECONOMY',
    military: 'LOC_MAD_LANE_MILITARY',
    growth: 'LOC_MAD_LANE_GROWTH',
    suzerain: 'LOC_MAD_LANE_SUZERAIN',
    arcadia: 'LOC_MAD_LANE_ARCADIA',
    foundations: 'LOC_MAD_LANE_FOUNDATIONS',
    surveyor: 'LOC_MAD_LANE_SURVEYOR',
    conquest: 'LOC_MAD_LANE_CONQUEST',
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

function laneForNoteId(modifierId) {
    const idx = modifierId.indexOf('_NOTE_');
    if (idx < 0) return 'other';
    const token = modifierId.substring(idx + 6).replace(/\d+$/, ''); // "SCIENCE2" -> "SCIENCE"
    return TOKEN_LANE[token] ?? 'other';
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

function currentTiers() {
    try {
        for (const [ageType, tiers] of Object.entries(AGE_TIERS)) {
            if (Game.age == Game.getHash(ageType)) return tiers;
        }
    } catch (e) { /* fall through */ }
    return AGE_TIERS.AGE_ANTIQUITY;
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

// city-states you lead: any player whose Influence.getSuzerain() names you (majors return
// -1), grouped by city-state type (the diplomacy panel's own read:
// GameInfo.CityStateTypes.lookup(player.getCityStateCityStateType()) → localized Name)
function suzerainCounts(playerId) {
    try {
        const all = Players.getAlive?.() ?? Players.getEverAlive?.() ?? [];
        let total = 0;
        const byType = new Map();
        for (const p of all) {
            try {
                if (p?.Influence?.getSuzerain?.() != playerId) continue;
                total++;
                let typeName = null;
                try {
                    const row = GameInfo.CityStateTypes.lookup?.(p.getCityStateCityStateType?.());
                    if (row?.Name) typeName = Locale.compose(row.Name);
                } catch (e) { /* type stays unknown */ }
                if (typeName) byType.set(typeName, (byType.get(typeName) ?? 0) + 1);
            } catch (e) { /* skip this player */ }
        }
        return { total, byType };
    } catch (e) {
        return null; // unknown — treat as "don't second-guess the card"
    }
}

function formatYieldChips(byYield, round = true) {
    const parts = [];
    for (const [yieldType, v] of Object.entries(byYield)) {
        if (!v) continue;
        const n = round ? Math.round(v * 10) / 10 : v;
        parts.push(`+${n} [icon:${yieldType}]`);
    }
    return parts.join('  ');
}

class MadDashboardPanel extends Panel {
    constructor() {
        super(...arguments);
        this.engineInputListener = this.onEngineInput.bind(this);
        this.refreshListener = this.refresh.bind(this);
        this.filter = 'all';
        this.collapsed = new Set(MadSettings.getCollapsedLanes()); // persisted; governs All/Active
        this.lockedExpanded = new Set(); // transient; Locked view starts fully collapsed
    }

    isLaneCollapsed(laneId) {
        return this.filter == 'locked'
            ? !this.lockedExpanded.has(laneId)
            : this.collapsed.has(laneId);
    }

    toggleLane(laneId) {
        if (this.filter == 'locked') {
            if (this.lockedExpanded.has(laneId)) this.lockedExpanded.delete(laneId);
            else this.lockedExpanded.add(laneId);
        } else {
            if (this.collapsed.has(laneId)) this.collapsed.delete(laneId);
            else this.collapsed.add(laneId);
            MadSettings.setCollapsedLanes([...this.collapsed]);
        }
        this.applyFilter();
    }

    // Expand all / Collapse all — drives whichever state set the CURRENT view uses:
    // All/Active share the persisted collapsed set; Locked has its own transient one.
    setAllLanes(expanded) {
        const laneIds = [...this.Root.querySelectorAll('.mad-lane')].map(l => l.dataset.lane);
        if (this.filter == 'locked') {
            if (expanded) for (const id of laneIds) this.lockedExpanded.add(id);
            else this.lockedExpanded.clear();
        } else {
            if (expanded) this.collapsed.clear();
            else for (const id of laneIds) this.collapsed.add(id);
            MadSettings.setCollapsedLanes([...this.collapsed]);
        }
        this.applyFilter();
    }

    onInitialize() {
        this.frame = MustGetElement('.mad-frame', this.Root);
        this.enableOpenSound = true;
        this.enableCloseSound = true;
    }

    onAttach() {
        this.Root.addEventListener(InputEngineEventName, this.engineInputListener);
        this.frame.addEventListener('subsystem-frame-close', () => { this.close(); });
        this.lockedExpanded.clear(); // Locked view starts compact on every visit
        for (const f of ['all', 'active', 'locked']) {
            const btn = this.Root.querySelector(`.mad-filter-${f}`);
            btn?.addEventListener('action-activate', () => this.setFilter(f));
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

    setFilter(f) {
        const changed = this.filter != f;
        this.filter = f;
        for (const name of ['all', 'active', 'locked']) {
            this.Root.querySelector(`.mad-filter-${name}`)?.classList.toggle('mad-filter-on', name == f);
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
    applyFilter() {
        const f = this.filter;
        let anyLaneVisible = false;
        for (const lane of this.Root.querySelectorAll('.mad-lane')) {
            const laneId = lane.dataset.lane;
            const isCollapsed = this.isLaneCollapsed(laneId);
            const chevron = lane.querySelector('.mad-chevron');
            if (chevron) chevron.textContent = isCollapsed ? '+' : '−';
            let anyMatch = false;
            for (const card of lane.querySelectorAll('.mad-card')) {
                const match = f == 'all'
                    || (f == 'active' && card.classList.contains('mad-active'))
                    || (f == 'locked' && card.classList.contains('mad-locked'));
                if (match) anyMatch = true;
                card.style.display = (match && !isCollapsed) ? '' : 'none';
            }
            for (const intro of lane.querySelectorAll('.mad-static')) {
                const state = intro.dataset.madState; // 'on' | 'off' | 'info'
                const match = f == 'all'
                    || (f == 'active' && state != 'off')
                    || (f == 'locked' && state == 'off');
                if (match) anyMatch = true;
                intro.style.display = (match && !isCollapsed) ? '' : 'none';
            }
            const laneVisible = (f == 'all' || anyMatch);
            lane.style.display = laneVisible ? '' : 'none';
            if (laneVisible) anyLaneVisible = true;
        }
        // fully-unlocked Age: the Locked view says so instead of going blank
        const emptyEl = this.Root.querySelector('.mad-locked-empty');
        if (emptyEl) emptyEl.style.display = (f == 'locked' && !anyLaneVisible) ? '' : 'none';
    }

    // ---------------------------------------------------------------- data

    collectCards(playerId) {
        // card key: gate node + lane + required depth -> one card with stacked note lines
        const cards = new Map();
        let rows = [];
        try {
            rows = GameInfo.ProgressionTreeNodeUnlocks.filter(u =>
                u.TargetKind == 'KIND_MODIFIER' &&
                typeof u.TargetType == 'string' &&
                u.TargetType.startsWith('MA_') &&
                u.TargetType.includes('_NOTE_') &&
                !u.Hidden);
        } catch (e) {
            console.error(`${TAG} ProgressionTreeNodeUnlocks read failed: ${e}`);
        }
        for (const u of rows) {
            const lane = laneForNoteId(u.TargetType);
            const depth = u.UnlockDepth ?? 1;
            const key = `${u.ProgressionTreeNodeType}|${lane}|${depth}`;
            let card = cards.get(key);
            if (!card) {
                const nodeRow = nodeInfoFor(u.ProgressionTreeNodeType);
                const unlockedDepth = unlockedDepthFor(nodeRow, playerId);
                card = {
                    lane,
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
        // the Suzerain card's payout needs an actual suzerained city-state on top of its
        // node — mark it DORMANT (unlocked but not paying) when you lead none
        const suzNote = `LOC_MA_${currentAgeSfx()}_NOTE_SUZERAIN`;
        const suz = suzerainCounts(playerId);
        for (const card of cards.values()) {
            if (card.lines.includes(suzNote)) {
                card.suzCount = suz?.total ?? null;
                card.suzByType = suz?.byType ?? null;
                card.dormant = (suz?.total === 0) &&
                    card.unlockedDepth != null && card.unlockedDepth >= card.requiredDepth;
            }
        }
        return [...cards.values()].filter(c => c.lines.length > 0);
    }

    collectVitals() {
        const vitals = {
            homeland: 0, distant: 0, tall: true,
            urbanPop: 0, happiness: null, stageLoc: null, stageIcon: null, tiers: currentTiers(),
        };
        try {
            const player = Players.get(GameContext.localPlayerID);
            const cities = player?.Cities?.getCities() ?? [];
            let metropolis = null;
            for (const city of cities) {
                if (city.isDistantLands) vitals.distant++; else vitals.homeland++;
                const urban = city.urbanPopulation ?? 0;
                if (!city.isTown && urban >= vitals.urbanPop) {
                    vitals.urbanPop = urban;
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
            vitals.tall = vitals.homeland <= 1 && vitals.distant <= 1;
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
        // engine-attributed MA income (labeled leaves); nothing to show while suspended
        this.impact = vitals.tall ? collectImpact() : { buckets: {}, total: {} };
        // computed influence: the two constructible-routed sources the engine can't label
        // (EFFECT_PLAYER_ADJUST_CONSTRUCTIBLE_YIELD): the Palace primer (active only at
        // exactly 1 settlement) and the Hub-town building bonus (node-gated, per building).
        this.primer = 0;      // Palace primer — shown on the Foundations chip
        this.hubInfluence = 0; // Hub-town building bonus — headline only (no single card owns it)
        try {
            const sfx = currentAgeSfx();
            if (vitals.tall && (vitals.homeland + vitals.distant) < 2) {
                this.primer += Number(modArg(`MA_${sfx}_SUZ_PRIMER`, 'Amount') ?? 0) || 0;
            }
            if (vitals.tall) {
                // per-age hub config mirrors gen-ascendant ($age.HubBuilding/$age.HubNode)
                const HUB = {
                    AQ: ['BUILDING_MONUMENT', 'NODE_TECH_AQ_MASONRY'],
                    EX: ['BUILDING_GUILDHALL', 'NODE_TECH_EX_GUILDS'],
                    MO: ['BUILDING_OPERA_HOUSE', 'NODE_TECH_MO_URBANIZATION'],
                }[sfx];
                const hubAmt = Number(modArg(`MA_${sfx}_HUB_INFLUENCE`, 'Amount') ?? 0) || 0;
                if (HUB && hubAmt) {
                    const nodeRow = nodeInfoFor(HUB[1]);
                    const depth = unlockedDepthFor(nodeRow, playerId);
                    if (depth != null && depth >= 1) {
                        const player = Players.get(playerId);
                        let count = 0;
                        for (const city of (player?.Cities?.getCities() ?? [])) {
                            if (city.Constructibles?.hasConstructible?.(HUB[0], false)) count++;
                        }
                        this.hubInfluence = hubAmt * count;
                    }
                }
            }
        } catch (e) { /* computed chips are a nicety */ }
        const extraInf = this.primer + this.hubInfluence;
        if (extraInf) this.impact.total.YIELD_DIPLOMACY = (this.impact.total.YIELD_DIPLOMACY ?? 0) + extraInf;
        this.renderVitals(vitals);
        this.renderLanes(cards, vitals);
        this.setFilter(this.filter);
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
            const parts = [
                `${Locale.compose('LOC_MAD_HOMELAND')} ${v.homeland}/1`,
                `${Locale.compose('LOC_MAD_DISTANT')} ${v.distant}/1`,
            ];
            if (!v.tall) parts.push(Locale.compose('LOC_MAD_SUSPENDED_HINT'));
            detail.textContent = parts.join('  ·  ');
        }
        if (pop) {
            const [t1, t2, t3] = v.tiers;
            const tier = v.urbanPop >= t3 ? 3 : v.urbanPop >= t2 ? 2 : v.urbanPop >= t1 ? 1 : 0;
            const next = tier >= 3 ? null : v.tiers[tier];
            const parts = [`${Locale.compose('LOC_MAD_URBAN_POP')} ${v.urbanPop}`];
            if (tier > 0) parts.push(`${Locale.compose('LOC_MAD_TIER')} ${tier} (T${tier})`);
            parts.push(next == null
                ? Locale.compose('LOC_MAD_TIERS_ALL')
                : `${Locale.compose('LOC_MAD_NEXT_TIER_WORD')} (T${tier + 1}) ${Locale.compose('LOC_MAD_UNLOCKS_AT')} ${next} ${Locale.compose('LOC_MAD_URBAN_WORD')}`);
            pop.textContent = parts.join('  ·  ');
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
        const impactEl = this.Root.querySelector('.mad-impact');
        if (impactEl) {
            const chips = MadSettings.showFigures ? formatYieldChips(this.impact?.total ?? {}) : '';
            impactEl.innerHTML = chips
                ? Locale.stylize(`${Locale.compose('LOC_MAD_IMPACT_NOW')}  ${chips} ${Locale.compose('LOC_MAD_PER_TURN')}`)
                : '';
        }
        this.frame.classList.toggle('mad-suspended', !v.tall);
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
        const nwFound = anyNaturalWonderFound(playerId);

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
                // live engine-attributed chips on the static sections
                let chipTxt = '';
                if (!MadSettings.showFigures) { /* plain catalog view */ }
                else if (lane == 'arcadia') {
                    const merged = {};
                    for (const key of ['LOC_MA_ARCADIA_DESCRIPTION', 'LOC_MA_ARCADIA_PEAKS_DESCRIPTION', 'LOC_MA_ARCADIA_WATERS_DESCRIPTION']) {
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
            for (const card of sorted) section.appendChild(this.renderCard(card));

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
        kind.textContent = Locale.compose(card.isCivic ? 'LOC_MAD_CIVIC' : 'LOC_MAD_TECH');
        head.appendChild(kind);
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
        if (stateUnknown) {
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
        if (isActive && MadSettings.showFigures) {
            const merged = {};
            const add = (byYield, onlyYield = null) => {
                for (const [yt, v] of Object.entries(byYield ?? {})) {
                    if (onlyYield && yt != onlyYield) continue;
                    merged[yt] = (merged[yt] ?? 0) + v;
                }
            };
            const sfx = currentAgeSfx();
            for (const lineKey of card.lines) add(this.impact?.buckets?.[lineKey]);
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
