// ============================================================================
//  Metropolis Ascendant — MA-native card price tags (task #27, 2026-07-22).
//  Stamps a live computed value line on every MA card in the policy chooser.
//
//  WHY: after CARD FIX v2 an MA card's above-floor copies ride the feat-reward
//  attach, so the companion preview mod's chooser chips (which price only the
//  modifiers bound to the card itself) read ZERO above 2 settlements while the
//  card actually pays. These chips compute the card's own formula from live
//  game state instead — they work with OR without the companion mod, and on MA
//  cards the companion's (wrong) box is hidden via a scoped CSS rule.
//
//  Card discovery mirrors the companion mod's proven 1.4.0 recipe: PolicyCard
//  mounts as `.policy-base-card` with no TraditionType in the DOM, so we match
//  the card's displayed name against GameInfo.Traditions (MA rows only).
//  Formulas come from the generated ui/cards/mad-card-formulas.js manifest.
// ============================================================================

const TAG = '[MA-CardChips]';
console.warn(`${TAG} loaded`);

// ---------- live-state reads ------------------------------------------------
function localCities() {
    try { return Players.get(GameContext.localPlayerID)?.Cities?.getCities() ?? []; }
    catch (e) { return []; }
}

function ageSfx() {
    try {
        if (Game.age == Game.getHash('AGE_ANTIQUITY')) return 'AQ';
        if (Game.age == Game.getHash('AGE_MODERN')) return 'MO';
    } catch (e) { /* fall through */ }
    return 'EX';
}

// Breathtaking appeal threshold (the base appeal-lens tier: general-appeal-layer.js).
let _breathThreshold = null;
function breathtakingThreshold() {
    if (_breathThreshold == null) {
        _breathThreshold = 5;
        try {
            const row = GameInfo.GlobalParameters.find(g => g.Name == 'APPEAL_FOR_DOUBLE_HAPPINESS_TILE_YIELD');
            if (row?.Value != null) _breathThreshold = Number(row.Value);
        } catch (e) { /* keep default */ }
    }
    return _breathThreshold;
}

// Ecstatic check: threshold-match the city's Happiness yield against GameInfo.HappinessStages
// (the base city-banner recipe, same as the dashboard vitals).
function isEcstatic(city) {
    try {
        const hy = city.Yields?.getYield?.(YieldTypes.YIELD_HAPPINESS);
        if (hy == null) return false;
        const row = GameInfo.HappinessStages.find(r => r.HappinessStageType == 'HAPPINESS_STAGE_ECSTATIC');
        return row ? hy >= (row.StageMinThreshold ?? Infinity) : false;
    } catch (e) { return false; }
}

// Suzerainties: total count + distinct City-State types (the dashboard's Protectorates read).
function suzerainties() {
    let total = 0;
    const types = new Set();
    try {
        const me = GameContext.localPlayerID;
        for (const p of (Players.getAlive?.() ?? [])) {
            try {
                if (p?.Influence?.getSuzerain?.() != me) continue;
                total++;
                const t = p.getCityStateCityStateType?.();
                const row = GameInfo.CityStateTypes.lookup?.(t);
                types.add(String(row?.CityStateType ?? t ?? total));
            } catch (e) { /* skip */ }
        }
    } catch (e) { /* zero */ }
    return { total, types: types.size };
}

function activeTradeRoutes() {
    try { return Number(Players.get(GameContext.localPlayerID)?.Trade?.countPlayerTradeRoutes?.() ?? 0) || 0; }
    catch (e) { return 0; }
}

function totalSpecialists() {
    let n = 0;
    for (const city of localCities()) {
        try {
            for (const plot of (city.getPurchasedPlots?.() ?? [])) {
                n += city.Workers?.getNumWorkersAtPlot?.(plot) || 0;
            }
        } catch (e) { /* skip city */ }
    }
    return n;
}

// Constructible types present on one plot (the companion mod's proven read).
function plotConstructibleTypes(x, y) {
    const out = [];
    try {
        for (const id of (MapConstructibles.getHiddenFilteredConstructibles(x, y) ?? [])) {
            const inst = Constructibles.getByComponentID(id);
            const row = inst ? GameInfo.Constructibles.lookup(inst.type) : null;
            if (row) out.push(row);
        }
    } catch (e) { /* empty */ }
    return out;
}

// ---------- per-formula computation -----------------------------------------
function computeFormula(f) {
    switch (f.t) {
        case 'perpop': {
            let list = localCities();
            if (f.cap) list = list.filter(c => { try { return c.isCapital; } catch (e) { return false; } });
            if (f.stage) list = list.filter(isEcstatic);
            let v = 0;
            for (const c of list) {
                let pop = 0;
                try {
                    const urban = c.urbanPopulation ?? 0;
                    pop = (f.pop == 'Rural') ? Math.max(0, (c.population ?? 0) - urban) : urban;
                } catch (e) { /* 0 */ }
                v += f.a * Math.floor(pop / (f.div || 1));
            }
            return v;
        }
        case 'suztype': return f.a * suzerainties().types;
        case 'persuz': {
            const t = suzerainties().total;
            const per = f.a * t;
            return f.cap ? per : per * localCities().length;
        }
        case 'trade': return f.a * activeTradeRoutes() * localCities().length;
        case 'worker': return f.a * totalSpecialists();
        case 'wonders': {
            let n = 0;
            for (const city of localCities()) {
                try {
                    for (const plot of (city.getPurchasedPlots?.() ?? [])) {
                        const loc = GameplayMap.getLocationFromIndex(plot);
                        if (plotConstructibleTypes(loc.x, loc.y).some(r => r.ConstructibleClass == 'WONDER')) n++;
                    }
                } catch (e) { /* skip */ }
            }
            return f.a * n;
        }
        case 'breath': {
            let n = 0;
            const th = breathtakingThreshold();
            for (const city of localCities()) {
                try {
                    for (const plot of (city.getPurchasedPlots?.() ?? [])) {
                        const loc = GameplayMap.getLocationFromIndex(plot);
                        if (GameplayMap.getAppeal(loc.x, loc.y) >= th) n++;
                    }
                } catch (e) { /* skip */ }
            }
            return f.a * n;
        }
        case 'plotpair': {
            const pair = f.pair?.[ageSfx()];
            if (!pair || pair.length < 2) return 0;
            let n = 0;
            for (const city of localCities()) {
                try {
                    for (const plot of (city.getPurchasedPlots?.() ?? [])) {
                        const loc = GameplayMap.getLocationFromIndex(plot);
                        const types = plotConstructibleTypes(loc.x, loc.y).map(r => r.ConstructibleType);
                        if (types.includes(pair[0]) && types.includes(pair[1])) n++;
                    }
                } catch (e) { /* skip */ }
            }
            return f.a * n;
        }
        default: return null;
    }
}

// ---------- rendering --------------------------------------------------------
let _cssInjected = false;
function injectCss() {
    if (_cssInjected) return;
    _cssInjected = true;
    const style = document.createElement('style');
    style.textContent = `
        /* Overlay, NOT layout: absolutely positioned inside the card so it can never change
           the card's size (2026-07-22 - the in-flow version stretched the whole card grid).
           FLEX row, not inline-block: Coherent's engine flows flex reliably; inline-block
           stacked the multi-pill cards vertically over the card text. */
        [data-mad-chip="1"] { position: relative; }
        .mad-chiprow {
            position: absolute; left: 0.125rem; right: 0.125rem; bottom: 0.125rem;
            display: flex; flex-direction: row; flex-wrap: wrap;
            justify-content: center; align-items: center;
            pointer-events: none;
        }
        .mad-chiprow .mad-chip-pill {
            flex: none; margin: 0.0625rem; padding: 0 0.3125rem;
            font-size: 0.75rem; font-weight: 600; letter-spacing: 0.02em; color: #e9e3d3;
            background: rgba(0, 0, 0, 0.6); border: 0.0625rem solid #c9a54e;
            border-radius: 0.5rem; white-space: nowrap;
        }
        /* On ALL MA cards the companion mod's box is hidden (post-card-fix its read
           only sees the floor copy and shows zero above 2 settlements). */
        [data-mad-card="1"] .yields-preview__root { display: none !important; }
    `;
    document.head.appendChild(style);
}

// MA TraditionTypes by localized display name (the companion mod's matching trick —
// PolicyCard exposes no TraditionType in the DOM).
let _maByName = null;
function maTraditionByName(displayedName) {
    if (_maByName == null) {
        _maByName = new Map();
        try {
            for (const t of GameInfo.Traditions) {
                if (!String(t.TraditionType).startsWith('TRADITION_MA_')) continue;
                const composed = String(Locale.compose(t.Name) ?? '').replace(/\s+/g, ' ').trim().toLowerCase();
                if (composed) _maByName.set(composed, t.TraditionType);
            }
        } catch (e) { /* leave empty */ }
    }
    return _maByName.get(String(displayedName ?? '').replace(/\s+/g, ' ').trim().toLowerCase());
}

function injectChip(card) {
    if (card.dataset.madChip) return;
    const nameEl = card.querySelector('.font-title.uppercase.text-sm.font-bold');
    const displayedName = nameEl?.textContent?.trim();
    if (!displayedName) return;
    const tid = maTraditionByName(displayedName);
    if (!tid) { card.dataset.madChip = '0'; return; }   // not an MA card — leave it alone
    // EVERY MA card suppresses the companion mod's box (even chipless ones like Esprit de
    // Corps / Spoils / The World Exchange — their card text carries the numbers, and the
    // companion's floor-copy read is wrong above 2 settlements either way).
    injectCss();
    card.dataset.madCard = '1';
    const formulas = (globalThis.MAD_CARD_FORMULAS ?? {})[tid];
    if (!formulas || !formulas.length) { card.dataset.madChip = '0'; return; }
    try {
        const parts = [];
        for (const f of formulas) {
            const v = computeFormula(f);
            if (v == null) continue;
            parts.push(`<span class="mad-chip-pill">${Locale.stylize(`${v >= 0 ? '+' : ''}${v}[icon:${f.y}]`)}</span>`);
        }
        if (!parts.length) { card.dataset.madChip = '0'; return; }
        const row = document.createElement('div');
        row.className = 'mad-chiprow';
        row.innerHTML = parts.join('');
        card.appendChild(row);
        card.dataset.madChip = '1';
    } catch (e) {
        console.error(`${TAG} chip failed for ${tid}:`, e);
        card.dataset.madChip = '0';
    }
}

function scan(root) {
    if (!(root instanceof HTMLElement)) return;
    if (root.classList?.contains('policy-base-card')) injectChip(root);
    root.querySelectorAll?.('.policy-base-card')?.forEach(injectChip);
}

const observer = new MutationObserver(muts => {
    for (const m of muts) for (const node of m.addedNodes) scan(node);
});
observer.observe(document.body, { childList: true, subtree: true });
