/**
 * Metropolis Ascendant — Ascendancy BOOST indicator (Civ6-style, on the card + in the pop-out). SHIPPING.
 *
 * TWO-STATE PILL. Every boostable Ascendancy node shows a small pill at the right of its card bar:
 *   • not yet earned  -> gold  "BOOST"
 *   • boost earned    -> blue  "BOOSTED"
 * The node's hover pop-out echoes it: a gold "BOOST" pill + the deed (warm text), which flips to a
 * blue "BOOSTED" pill + blue deed once earned. (Replaces the old full-card blue glow, which Chris
 * found too heavy — 2026-07-15.)
 *
 * WHY PSEUDO-ELEMENTS. The engine's UI reconciliation deletes any child element we inject into a card
 * on redraw — only STYLE effects on existing elements survive. So the pill is a CSS ::after (content
 * baked in the stylesheet), toggled by adding a class to the card bar. Coherent honours injected class
 * rules with LITERAL colours (it ignores var() and content:attr()), so all values are literal.
 *
 * EARNED DETECTION (approach B, verified in-game). Civ7 commingles boost + research progress into one
 * number with no boost flag. Each boost has a companion modifier (MA_BOOSTMARK_*) that sets a player
 * property MA_BOOST_<nodeType>=1 when its deed fires; we read it directly — research can never set it:
 *     Players.get(pid).getProperty(Database.makeHash('MA_BOOST_' + nodeType)) >= 1  -> boosted.
 * (⚠ the marker modifiers bind at game creation, so this only reflects games started after the mod
 * added them.) A completed (fully-researched) node shows no pill — the boost is moot.
 *
 * POP-OUT LINKAGE. The "Boost:" line is authored in the node's detail text as
 * [STYLE:mad-boost][STYLE:mad-boost-k]Boost[/S] <deed>[/S]; the panel renders it via Locale.stylize
 * -> <span class="mad-boost"><span class="mad-boost-k">Boost</span> deed</span>. The chip lives in a
 * hover tooltip that carries no node id, so we read the hovered card (it gains a `hover` class) and,
 * if its node is earned, add `.ma-earned` to the chip (blue pill + "BOOSTED" + blue deed).
 *
 * Pure UI, additive, fully try/catch'd. Runs from MA's dashboard-game UIScripts.
 */

const CARD_SEL = 'tree-card-v2[type]';
// The 13 boostable web nodes (every Ascendancy node except the repeatable Rites + hidden Charter/
// mastery nodes). Matches all three Ages.
const BOOSTABLE = /^NODE_MA_(AQ|EX|MO)_(SCI1|SCI2|CUL1|CUL2|ECO1|ECO2|EXP1|EXP2|MIL1|IND1|DIP1|DIP2|BRIDGE1)$/;

// One stylesheet for both surfaces (card pills + pop-out chip). Literal colours only.
(function injectBoostStyle() {
    try {
        if (document.getElementById('mad-boost-style')) return;
        const st = document.createElement('style');
        st.id = 'mad-boost-style';
        st.textContent =
            // ---- card pills (CSS ::after; survives reconciliation) ----
            '.ma-boost-badge,.ma-boosted-badge{position:relative;}'
          + '.ma-boost-badge::after,.ma-boosted-badge::after{position:absolute;top:50%;right:16px;'
          + 'transform:translateY(-50%);font-family:sans-serif;font-size:9px;font-weight:700;'
          + 'letter-spacing:.13em;padding:2px 9px;border-radius:4px;box-shadow:0 1px 3px rgba(0,0,0,.55);'
          + 'pointer-events:none;z-index:20;}'
          + '.ma-boost-badge::after{content:"BOOST";background:linear-gradient(180deg,#f2d488,#d3a233);'
          + 'color:#2a1c06;border:1px solid #8a6318;}'
          + '.ma-boosted-badge::after{content:"BOOSTED";background:linear-gradient(180deg,#7ec0f2,#3f8fce);'
          + 'color:#062338;border:1px solid #205f8c;}'
            // ---- pop-out chip: small pill label + deed on its own line (no box -> no overlap) ----
          + '.mad-boost{display:block;margin-top:7px;color:#ecdfc2;font-size:1em;line-height:1.4;}'
          + '.mad-boost-k{display:inline-block;background:linear-gradient(180deg,#f2d488,#d3a233);'
          + 'color:#2a1c06;text-transform:uppercase;letter-spacing:.1em;font-weight:700;font-size:.72em;'
          + 'padding:1px 7px 2px;border-radius:3px;margin-right:8px;vertical-align:middle;}'
            // earned variant (blue pill + "BOOSTED" + blue deed)
          + '.mad-boost.ma-earned{color:#a6cbec;}'
          + '.mad-boost.ma-earned .mad-boost-k{background:linear-gradient(180deg,#7ec0f2,#3f8fce);'
          + 'color:#062338;font-size:0;}'
          + '.mad-boost.ma-earned .mad-boost-k::after{content:"BOOSTED";font-size:11px;letter-spacing:.08em;}';
        (document.head || document.documentElement).appendChild(st);
    } catch (e) { /* head not ready; harmless */ }
})();

function pid() { try { return GameContext.localPlayerID; } catch (e) { return -1; } }

function maNodeType(typeHash) {
    try {
        const info = GameInfo?.ProgressionTreeNodes?.lookup?.(Number(typeHash));
        const s = String(info?.ProgressionTreeNodeType || '');
        return s.startsWith('NODE_MA_') ? s : '';
    } catch (e) { return ''; }
}

// The boost marker is set AND the node isn't yet fully researched.
function isEarnedBoost(p, typeHash) {
    const nt = maNodeType(typeHash);
    if (!nt) return false;
    let flag = 0;
    try { const v = Players.get(p)?.getProperty(Database.makeHash('MA_BOOST_' + nt)); if (typeof v === 'number') flag = v; } catch (e) {}
    if (flag < 1) return false;
    return !isComplete(p, typeHash);
}

function isComplete(p, typeHash) {
    // FIXED 2026-07-26 (GitHub #27; FireTuner-diagnosed): node.progress is WORKING state — the
    // engine RESETS it to 0 at completion, so the old `progress >= cost` test read 0 >= cost =
    // false forever and a completed node wore its BOOSTED badge permanently. depthUnlocked is
    // the durable completion signal (>= 1 = base research done; the boost's 40% only ever pays
    // the first research, so moot-at-checkmark is correct even mid-mastery).
    // ⚠ typeHash arrives as the card's `type` ATTRIBUTE = a STRING of digits; getNode needs the
    // NUMBER (same reason maNodeType wraps lookup in Number()). Without the coercion getNode
    // returns nothing and this reads never-complete — which is also why the ORIGINAL
    // progress>=cost version never worked: its progress read came from the same failed call.
    try { const n = Game.ProgressionTrees.getNode(p, Number(typeHash)); return ((n && n.depthUnlocked) || 0) >= 1; }
    catch (e) { return false; }
}

// The visible rounded bar (fall back through the card layers, then the host).
function barTarget(el) {
    try { return el.querySelector('.tree-card-hitbox') || el.querySelector('.tree-card-bg') || el; }
    catch (e) { return el; }
}

function paintCard(el, p) {
    const bar = barTarget(el);
    if (!bar) return;
    try {
        bar.classList.remove('ma-boost-badge', 'ma-boosted-badge');
        bar.style.removeProperty('box-shadow');   // clear any legacy glow
        const type = el.getAttribute('type');
        if (!BOOSTABLE.test(maNodeType(type))) return;
        if (isEarnedBoost(p, type)) bar.classList.add('ma-boosted-badge');
        else if (!isComplete(p, type)) bar.classList.add('ma-boost-badge');
    } catch (e) {}
}

// The hover tooltip carries no node id, so link it to the hovered card and flip the chip if earned.
function paintChips(cards, p) {
    let chips;
    try { chips = document.querySelectorAll('.mad-boost'); } catch (e) { return; }
    if (!chips.length) return;
    let earned = false;
    try {
        for (const el of cards) {
            const cl = typeof el.className === 'string' ? el.className : '';
            if (/hover/i.test(cl)) { earned = isEarnedBoost(p, el.getAttribute('type')); break; }
        }
    } catch (e) {}
    chips.forEach((ch) => { try { ch.classList.toggle('ma-earned', earned); } catch (e) {} });
}

function update() {
    try {
        const cards = document.querySelectorAll(CARD_SEL);
        if (!cards.length) return false;
        const p = pid();
        cards.forEach((el) => { try { paintCard(el, p); } catch (e) {} });
        paintChips(cards, p);
        return true;
    } catch (e) { return false; }
}

let frame = 0;
function tick() {
    try { frame++; if (frame % 12 === 0) update(); } catch (e) {}
    try { requestAnimationFrame(tick); } catch (e) {}
}
class BoostScreen {
    constructor(component) { this.c = component; try { requestAnimationFrame(() => this.loop()); } catch (e) {} }
    loop() {
        try { update(); } catch (e) {}
        try { requestAnimationFrame(() => this.loop()); } catch (e) {}
    }
    beforeAttach() {} afterAttach() {} beforeDetach() {} afterDetach() {}
}

try { requestAnimationFrame(tick); } catch (e) {}
try { Controls.decorate('screen-culture-tree', (c) => new BoostScreen(c)); } catch (e) {}
