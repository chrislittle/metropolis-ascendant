// ============================================================================
// Metropolis Ascendant — tree tooltip UX (GitHub #27; litmus-proven 2026-07-26).
//
//   A: the tooltip's cost pill IS the progress bar — gold fill + "25/63"
//      fraction while researching; completed = the pill itself tinted solid
//      gold via class (NOT a width overlay: Coherent renders width:100% short
//      of the right edge — proven in the litmus).
//   1: ONE boost surface in the pop-out — "the card badge says WHETHER, the
//      box says WHAT". MA's authored deed line ([STYLE:mad-boost] span, which
//      the game renders inside the tooltip) is LIFTED out of the benefit text
//      into a section-row box above the cost: gold BOOST + deed → blue
//      BOOSTED once the MA_BOOST_* marker fires → NOTHING once the node
//      completes (completion is already told by the header, the checkmark,
//      and the solid-gold pill). Base trees have no boosts → no box, ever;
//      they get the progress treatment only.
//
// MECHANISM — the Portal-observer patch: TechCivicTooltip is a Solid
// component rendered via <Portal> into #uinext-tooltips (no legacy component
// to Controls.decorate), so we observe the portal root and patch each tooltip
// after it mounts. Insertion anchors on the tooltip's REAL structure (read
// from base tech-civic-tooltip.js): .tech-civic-tooltip > Tooltip.Frame >
// [header, unlock sections, cost row .flex-wrap]. Absent beats detached: if
// an anchor is missing, we skip rather than fall back to the root.
//
// Verified in live play across: base tech tree, base civics tree, both
// chooser side panels, the Ascendancy tree, all three boost states, and the
// 40% deed payment landing visibly in the pill (25/63 = 0.4 x 63).
// Pure UI, additive, fully try/catch'd.
// ============================================================================

(() => {
    // Literal colours only — Coherent ignores var(). Gradients = MA's boost
    // visual language (matches the mad-boost-glow card badges).
    function injectStyle() {
        try {
            if (document.getElementById('mad-treeux-style')) return;
            const st = document.createElement('style');
            st.id = 'mad-treeux-style';
            st.textContent =
                '.mad-ux-pill{position:relative;overflow:hidden;}'
              + '.mad-ux-fill{display:block;position:absolute;top:0;left:0;bottom:0;pointer-events:none;'
              + 'background:linear-gradient(180deg,rgba(242,212,136,.30),rgba(211,162,51,.22));'
              + 'border-right:1px solid rgba(242,212,136,.55);}'
              + '.mad-ux-pilltext{position:relative;}'
              + '.mad-ux-done{background-image:linear-gradient(180deg,rgba(242,212,136,.34),rgba(211,162,51,.26));}'
              + '.mad-ux-boost{display:block;margin:8px 0 0;padding:8px 11px;border-radius:3px;'
              + 'background:rgba(64,48,14,.20);border:1px solid #8a6318;color:#e6d9b8;'
              + 'font-size:13px;line-height:1.45;}'
              + '.mad-ux-boost.mad-ux-earned{border-color:#205f8c;background:rgba(12,38,58,.30);'
              + 'color:#b9d7ef;}'
              + '.mad-ux-boost-k{display:inline-block;background:linear-gradient(180deg,#f2d488,#d3a233);'
              + 'color:#2a1c06;text-transform:uppercase;letter-spacing:.11em;font-weight:700;font-size:10px;'
              + 'padding:1px 8px 2px;border-radius:3px;margin-right:8px;vertical-align:middle;}'
              + '.mad-ux-boost.mad-ux-earned .mad-ux-boost-k{'
              + 'background:linear-gradient(180deg,#7ec0f2,#3f8fce);color:#062338;}';
            (document.head || document.documentElement).appendChild(st);
        } catch (e) { /* head not ready; harmless */ }
    }

    function costPillOf(tooltip) {
        try {
            const pills = tooltip.querySelectorAll('.rounded-full');
            return pills.length ? pills[pills.length - 1] : null;
        } catch (e) { return null; }
    }

    // ---- A: fraction + proportional gold fill inside the native cost pill ----
    function patchCostPill(tooltip, progressValue, cost, costIconStr) {
        try {
            const pill = costPillOf(tooltip);
            if (!pill) return;
            const pct = Math.max(0, Math.min(100, Math.round(progressValue / cost * 100)));
            pill.classList.add('mad-ux-pill');
            pill.classList.toggle('mad-ux-done', pct >= 100);
            pill.innerHTML =
                (pct > 0 && pct < 100 ? `<span class="mad-ux-fill" style="width:${pct}%"></span>` : '')
              + `<span class="mad-ux-pilltext">`
              + Locale.stylize('LOC_CARD_COST', `${progressValue}/${cost}${costIconStr}`)
              + `</span>`;
        } catch (e) { /* never break the tooltip */ }
    }

    // ---- boost earned = the deed's marker property (mad-boost-glow's shipped
    //      detection; research can never set it) ----
    function isBoostEarned(nodeTypeHash) {
        try {
            const info = GameInfo?.ProgressionTreeNodes?.lookup?.(Number(nodeTypeHash));
            const nt = String(info?.ProgressionTreeNodeType || '');
            if (!nt.startsWith('NODE_MA_')) return false;
            const p = Players.get(GameContext.localPlayerID);
            if (!p?.getProperty) return false;
            return (p.getProperty(Database.makeHash('MA_BOOST_' + nt)) ?? 0) >= 1;
        } catch (e) { return false; }
    }

    // ---- 1: consolidate the boost into one section-row box above the cost ----
    function consolidateBoost(tooltip, isCompleted, nodeTypeHash) {
        try {
            if (tooltip.querySelector('.mad-ux-boost')) return;     // one per tooltip

            // Source of truth for "this node has a boost": MA's authored deed
            // line, already rendered into the tooltip by the game.
            const authored = tooltip.querySelector('.mad-boost');
            if (!authored) return;                                  // no boost -> no box

            const clone = authored.cloneNode(true);
            clone.querySelector('.mad-boost-k')?.remove();          // drop the inline "Boost" keyword
            const deed = (clone.textContent || '').trim();
            authored.remove();                                      // the in-text line goes away
            if (!deed) return;

            // Completed node: boost is moot — line removed above, nothing shown.
            if (isCompleted) return;

            const earned = isBoostEarned(nodeTypeHash);
            const box = document.createElement('div');
            box.className = 'mad-ux-boost' + (earned ? ' mad-ux-earned' : '');
            box.innerHTML =
                `<span class="mad-ux-boost-k">${earned ? 'BOOSTED' : 'BOOST'}</span>${deed}`;

            const pill = costPillOf(tooltip);
            const row = (pill && (pill.closest('.flex-wrap') || pill.parentElement)) || null;
            if (row && row.parentElement) {
                row.parentElement.insertBefore(box, row);
            } else if (pill && pill.parentElement) {
                pill.parentElement.insertBefore(box, pill);
            }
            // no root fallback — absent beats detached
        } catch (e) { /* never break the tooltip */ }
    }

    // ---- context 1: hovered tree card (base trees AND the Ascendancy tree) ----
    function fromTreeCard(tooltip, card) {
        const cost = parseInt(card.getAttribute('cost') || '0', 10);
        if (!cost) return;
        const isCulture = card.getAttribute('tree-type') === 'culture';
        const icon = isCulture ? '[icon:YIELD_CULTURE]' : '[icon:YIELD_SCIENCE]';
        const progress = parseFloat(card.getAttribute('progress') || '0');

        let level = 1;
        try {
            const hitbox = card.querySelector('fxs-activatable.tree-card-hitbox:hover');
            level = hitbox?.classList.contains('parent-node') ? 0 : 1;
        } catch (e) { /* default */ }

        let unlocksByDepth = [];
        try { unlocksByDepth = JSON.parse(card.getAttribute('unlocks-by-depth') || '[]'); }
        catch (e) { return; }

        const depth = unlocksByDepth[level];
        let progressValue;
        if (!depth || depth.isLocked)   progressValue = 0;
        else if (depth.isCompleted)     progressValue = cost;
        else                            progressValue = Math.round(progress / 100 * cost);

        patchCostPill(tooltip, progressValue, cost, icon);
        consolidateBoost(tooltip, !!depth?.isCompleted, card.getAttribute('type'));
    }

    // ---- context 2: chooser side panels. ⚠ ChooserItem's root is a plain
    //      <div> with classes (activatable.js) — select by class, never tag. ----
    function fromChooserItem(tooltip, el) {
        const nodeId = parseInt(el.getAttribute('node-id') || '0', 10);
        if (!nodeId) return;
        const player = Players.get(GameContext.localPlayerID);
        if (!player) return;

        const isCulture = el.classList.contains('culture-item');
        const cost = isCulture
            ? (player.Culture?.getNodeCost?.(nodeId) ?? -1)
            : (player.Techs?.getNodeCost?.(nodeId) ?? -1);
        if (cost <= 0) return;

        // ⚠ node.progress is WORKING state (zeroed at completion) — fine here
        // because the choosers only list researchABLE nodes; never use it as a
        // completion test (that's the depthUnlocked law).
        const nodeData = Game.ProgressionTrees.getNode?.(player.id, nodeId);
        const progress = nodeData?.progress ?? 0;   // raw points in this context
        const progressValue = Math.min(Math.round(progress), cost);

        patchCostPill(tooltip, progressValue, cost,
            isCulture ? '[icon:YIELD_CULTURE]' : '[icon:YIELD_SCIENCE]');
        consolidateBoost(tooltip, progressValue >= cost, nodeId);
    }

    function onTooltipMounted(tooltip) {
        injectStyle();
        // Trigger-context recovery via native :hover — the tooltip carries no node id.
        const card = document.querySelector('tree-card-v2:hover');
        if (card) { fromTreeCard(tooltip, card); return; }
        const item = document.querySelector('.tech-item[node-id]:hover, .culture-item[node-id]:hover');
        if (item) fromChooserItem(tooltip, item);
    }

    // Observe the tooltip PORTAL ROOT, not document.body — every ui-next tooltip
    // mounts here via <Portal mount={tooltipRoot}>; this element only churns
    // when a tooltip opens/closes.
    const root = document.getElementById('uinext-tooltips') ?? document.body;
    try {
        new MutationObserver((mutations) => {
            for (const m of mutations) {
                for (const node of m.addedNodes) {
                    if (node.nodeType !== 1) continue;
                    const tip = node.classList?.contains('tech-civic-tooltip')
                        ? node
                        : node.querySelector?.('.tech-civic-tooltip');
                    if (tip) onTooltipMounted(tip);
                }
            }
        }).observe(root, { childList: true, subtree: true });
    } catch (e) { /* observer unavailable: feature silently absent */ }
})();
