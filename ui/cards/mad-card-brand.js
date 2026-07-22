/**
 * Metropolis Ascendant — policy / tradition card branding (Option B: lane colours + emblem badge).
 *
 * Proven against the LIVE DOM via the Coherent debugger (port 9444) 2026-07-14:
 *   - the card is a `div.policy-base-card` (the tradition/policy chooser card), NOT a <policy-card>.
 *   - the name title is `.font-title.uppercase.text-sm.font-bold`; its text = the card name.
 *   - the tradition type isn't a queryable DOM attribute, so match by displayed name.
 *   - ⚠ COHERENT IGNORES `var(--x)` for colour (same dead-end as the dashboard) — colours MUST be set
 *     INLINE from JS. So the rail + badge are injected DIVs with inline hex styles, not CSS-class colours.
 *
 * Cosmetic + fail-safe: if the base DOM changes, cards still render + slot; they just lose the styling.
 */
const TAG = '[ma-card-brand]';

// The real MA emblem (screenshots/logo-emblem.svg) as compact inline SVG (solid gold; the gradient is
// invisible at badge size and solid fill dodges gradient-id clashes across instances). Exported for the
// dock decorator's "Emblem" icon option.
export const MAD_EMBLEM_SVG =
  '<svg class="mad-emblem" viewBox="0 0 360 360" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
  + '<g transform="translate(-150,62) scale(0.66)">'
  + '<path d="M500 60 L735 250 L690 250 L500 102 L310 250 L265 250 Z" fill="#caa03e" opacity="0.5"/>'
  + '<path d="M500 130 L660 260 L624 260 L500 160 L376 260 L340 260 Z" fill="#caa03e" opacity="0.5"/>'
  + '<g fill="#E7C062" stroke="#241704" stroke-width="4" stroke-linejoin="round">'
  + '<rect x="372" y="232" width="34" height="78"/><rect x="594" y="232" width="34" height="78"/>'
  + '<rect x="416" y="198" width="38" height="112"/><rect x="546" y="198" width="38" height="112"/>'
  + '<rect x="463" y="150" width="34" height="160"/><rect x="503" y="150" width="34" height="160"/>'
  + '<rect x="478" y="120" width="44" height="190"/><path d="M478 120 L500 70 L522 120 Z"/></g>'
  + '<path d="M500 36 L510 64 L539 64 L515 82 L524 110 L500 92 L476 110 L485 82 L461 64 L490 64 Z" '
  + 'fill="#E7C062" stroke="#241704" stroke-width="3" stroke-linejoin="round"/>'
  + '<rect x="320" y="312" width="360" height="10" rx="5" fill="#E7C062" stroke="#241704" stroke-width="3"/>'
  + '</g></svg>';

// Lane → colour (inline; Coherent won't resolve CSS vars). Policy cards carry the lane in their id
// (_SCI_/…); Major-feat cards (TRADITION_MA_MAJOR_<KEY>) mapped by feat lane.
const LANE_HEX = { sci: '#63b1de', cul: '#b184e0', gold: '#d8b45c', food: '#84c76f', dip: '#57cdba', mil: '#df9560', house: '#d8b45c' };
function laneFor(tt) {
    if (/_SCI_|_(ALMA|GRAND|OMNI)$/.test(tt)) return 'sci';
    if (/_CUL_|_(CROWN|BEAUT|MAGNUM)$/.test(tt)) return 'cul';
    if (/_ECO_|_TRADE_|_(COUNT|GOLDT|WEXCH)$/.test(tt)) return 'gold';
    if (/_EXP_|_LPEACE$/.test(tt)) return 'food';
    if (/_DIP_|_(LEAGUE|PAXM)$/.test(tt)) return 'dip';
    if (/_ESPRIT_|_SPOILS_/.test(tt)) return 'mil';
    return 'house'; // TRADEOFF + any other MA card → neutral MA gold
}

// displayed-name(lowercased) → lane, built once from GameInfo.Traditions (MA rows only)
let NAME_LANE = null;
function nameLaneMap() {
    if (NAME_LANE) return NAME_LANE;
    NAME_LANE = new Map();
    try {
        for (const t of GameInfo.Traditions) {
            if (typeof t.TraditionType != 'string' || !t.TraditionType.startsWith('TRADITION_MA_')) continue;
            const nm = Locale.compose(t.Name);
            if (nm) NAME_LANE.set(nm.trim().toLowerCase(), laneFor(t.TraditionType));
        }
    } catch (e) { console.error(`${TAG} tradition map failed: ${e}`); }
    return NAME_LANE;
}

function brandCard(card) {
    try {
        const titleEl = card.querySelector('.font-title.uppercase.text-sm.font-bold');
        const nm = (titleEl && titleEl.textContent || '').trim().toLowerCase();
        if (!nm) return;                                 // title not painted yet — a rescan catches it
        const lane = nameLaneMap().get(nm);
        if (!lane) return;                               // not one of ours
        const col = LANE_HEX[lane];
        if (getComputedStyle(card).position == 'static') card.style.position = 'relative';
        // lane colour rail down the left edge (inline colour — CSS vars don't render in Coherent)
        if (!card.querySelector('.mad-rail')) {
            const r = document.createElement('div');
            r.className = 'mad-rail';
            r.style.cssText = 'position:absolute;left:0;top:12%;bottom:12%;width:5px;border-radius:0 3px 3px 0;'
                + 'background:' + col + ';box-shadow:0 0 8px ' + col + ';z-index:30;pointer-events:none';
            card.appendChild(r);
        }
        // SWAP the stock icon in place (proven via the live debugger): the base icon is two blp images —
        // .policy-card-icon-backer (the 50x50 hexagon) + .policy-card-icon (the diamond, -ml-5 so it sticks
        // out left). Hide the diamond, and restyle the backer element itself into the gold disc + emblem, so
        // it sits at the exact slot the game positions — nothing pokes out. (Overlaying a separate badge left
        // the hexagon corners showing.)
        // Style the NON-greyscale icon backer as the disc + emblem. (The greyscale placeholder backers —
        // the card's own dual-slot indicator AND empty-slot / behind-slot sockets — are hidden globally in
        // rescan(), which is cleaner than a per-card guess. See hideGraySockets().)
        const backers = [...card.querySelectorAll('.policy-card-icon-backer')];
        const main = backers.find(b => !/policy-grayscale/.test(typeof b.className === 'string' ? b.className : ''));
        if (main) {
            const diamond = main.querySelector('.policy-card-icon');   // the diamond (child) — hide its art
            if (diamond) diamond.style.backgroundImage = 'none';
            if (!main.querySelector('.mad-emblem')) {
                main.style.backgroundImage = 'none';
                main.style.borderRadius = '50%';
                main.style.border = '1.5px solid ' + col;
                main.style.background = 'radial-gradient(circle at 38% 32%,#322820,#141009)';
                main.style.boxShadow = '0 0 9px ' + col + ',0 2px 5px rgba(0,0,0,.7)';
                main.style.overflow = 'hidden';
                main.style.transform = 'translateX(-18px)';   // shift into the gutter, clear of the text (starts ~x:43)
                main.style.zIndex = '33';                      // sit ABOVE the rail (z:30) so the rail passes behind the disc
                main.insertAdjacentHTML('beforeend', MAD_EMBLEM_SVG);
                const svg = main.querySelector('.mad-emblem');
                if (svg && svg.style) svg.style.cssText = 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);width:82%;height:82%;display:block';
            }
        }
    } catch (e) { /* per-card, never fatal */ }
}

// Hide the base game's greyscale slot-placeholder sockets everywhere (Chris's call 2026-07-14: cleaner —
// empty slots show no placeholder icon, and no dual-slot socket pokes out behind a slotted MA card). These
// are `.policy-card-icon-backer.policy-grayscale` (the accent_hex/circle placeholder art); a card's OWN icon
// backer is non-greyscale and is untouched. Robust global rule, no per-card position guessing.
function hideGraySockets() {
    for (const b of document.querySelectorAll('.policy-card-icon-backer')) {
        if (/policy-grayscale/.test(typeof b.className === 'string' ? b.className : '')) b.style.display = 'none';
    }
}

let pending = false;
function rescan() {
    pending = false;
    try {
        hideGraySockets();
        document.querySelectorAll('.policy-base-card').forEach(brandCard);  // idempotent per card
    } catch (e) { /* screen not up */ }
}
try {
    const obs = new MutationObserver(() => { if (!pending) { pending = true; requestAnimationFrame(rescan); } });
    obs.observe(document.body, { childList: true, subtree: true });
    rescan();
} catch (e) { console.error(`${TAG} observer failed: ${e}`); }
