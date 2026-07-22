/**
 * ma-bonus-dashboard — sub-system dock entry point + hotkey.
 * Adds a "Metropolis Dashboard" button to the in-game sub-system dock (optional via
 * Options → Mods) and toggles the panel on the open-ma-dashboard hotkey (default F7).
 *
 * Patterns: Controls.decorate('panel-sub-system-dock') + panel.addButton(...) and
 * ContextManager.registerEngineInputHandler → window 'hotkey-…' CustomEvent, as used
 * by Drongo's Cheat Panel / City Planner (additive — coexists with other mods).
 */
import ContextManager from '/core/ui/context-manager/context-manager.js';
import { InterfaceMode } from '/core/ui/interface-modes/interface-modes.js';
import MadSettings from 'fs://game/metropolis-ascendant/ui/options/mad-options.js';
import { MAD_EMBLEM_SVG } from 'fs://game/metropolis-ascendant/ui/cards/mad-card-brand.js';

// Swap the dock button's icon for the inline-SVG emblem (always on — the classic PNG stays only as a
// fallback in mad-dock.css if this decorator ever fails to run). Retries a few frames because the button
// DOM lands a tick after addButton().
function applyDockEmblem(panel, tries = 6) {
    try {
        const root = panel?.Root ?? document;
        const icon = root.querySelector?.('.tut-ma-dashboard .ssb__button-icon')
            ?? document.querySelector('.tut-ma-dashboard .ssb__button-icon');
        if (icon) {
            if (!icon.querySelector('.mad-emblem')) {
                icon.classList.add('mad-dock-emblem');
                icon.insertAdjacentHTML('beforeend', MAD_EMBLEM_SVG);
            }
            return;
        }
        if (tries > 0) requestAnimationFrame(() => applyDockEmblem(panel, tries - 1));
    } catch (e) { /* cosmetic only */ }
}

Controls.loadStyle('fs://game/metropolis-ascendant/ui/dock/mad-dock.css');

const PANEL_TAG = 'panel-ma-dashboard';
const HOTKEY_ACTION = 'open-ma-dashboard';

function toggleDashboard() {
    try {
        const currentTarget = ContextManager.getCurrentTarget?.();
        if (currentTarget?.tagName == PANEL_TAG.toUpperCase()) {
            ContextManager.pop(currentTarget);
            return;
        }
        ContextManager.push(PANEL_TAG, { singleton: true, createMouseGuard: true });
    }
    catch (e) {
        console.error(`[ma-bonus-dashboard] failed to toggle panel: ${e}`);
    }
}

class MadHotkeyInputManager {
    handleInput(inputEvent) {
        if (inputEvent.detail.status == InputActionStatuses.FINISH && inputEvent.detail.name === HOTKEY_ACTION) {
            if (InterfaceMode.allowsHotKeys()) {
                window.dispatchEvent(new CustomEvent(`hotkey-${HOTKEY_ACTION}`));
            }
            return false;
        }
        return true;
    }
}

class MadSubsystemDockDecorator {
    constructor(panel) {
        this._panel = panel;
    }

    beforeAttach() {
    }

    afterAttach() {
        if (!MadSettings.showDockButton) return;
        this._panel.addButton({
            tooltip: 'LOC_MAD_OPEN',
            modifierClass: 'unlocks',
            callback: toggleDashboard,
            class: 'tut-ma-dashboard',
            audio: 'unlocks',
            focusedAudio: 'data-audio-focus-small'
        });
        applyDockEmblem(this._panel);
    }

    beforeDetach() {
    }

    afterDetach() {
    }
}

ContextManager.registerEngineInputHandler(new MadHotkeyInputManager());
window.addEventListener(`hotkey-${HOTKEY_ACTION}`, toggleDashboard);
Controls.decorate('panel-sub-system-dock', (panel) => new MadSubsystemDockDecorator(panel));
