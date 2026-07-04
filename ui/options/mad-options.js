/**
 * ma-bonus-dashboard — settings + Options→Mods entries.
 * Loaded in BOTH shell and game scopes (the Options screen exists in both).
 *
 * Storage follows the community convention: ALL mods share the single localStorage
 * key "modSettings" (a second key breaks reads for every mod), namespaced per mod,
 * with the engine user-options store as the durable backend (bz-city-hall pattern).
 */
import '/core/ui/options/screen-options.js';
import { CategoryType, Options, OptionType } from '/core/ui/options/model-options.js';
import { CategoryData } from '/core/ui/options/options-helpers.js';

const MOD_ID = 'ma-bonus-dashboard';
const TAG = '[ma-bonus-dashboard]';

CategoryType["Mods"] = "mods";
CategoryData[CategoryType.Mods] ??= {
    title: "LOC_UI_CONTENT_MGR_SUBTITLE",
    description: "LOC_UI_CONTENT_MGR_SUBTITLE_DESCRIPTION",
};

function readStore() {
    try {
        const parsed = JSON.parse(localStorage.getItem('modSettings') || '{}');
        return (parsed && typeof parsed == 'object' && !Array.isArray(parsed)) ? parsed : {};
    } catch (e) { return {}; }
}

const MadSettings = new class {
    defaults = { showFigures: true, showDockButton: true, collapsedLanes: [] };
    data = null;

    loadAll() {
        if (this.data) return this.data;
        this.data = { ...this.defaults };
        try {
            const mine = readStore()[MOD_ID];
            if (mine && typeof mine == 'object') this.data = { ...this.defaults, ...mine };
        } catch (e) { console.error(`${TAG} settings load failed: ${e}`); }
        // durable backend wins where present
        try {
            for (const key of ['showFigures', 'showDockButton']) {
                const v = UI.getOption('user', 'Mod', `${MOD_ID}.${key}`);
                if (v != null) this.data[key] = Boolean(Number(v));
            }
        } catch (e) { /* localStorage copy stands */ }
        return this.data;
    }

    save() {
        try {
            const store = readStore();
            store[MOD_ID] = this.data;
            localStorage.setItem('modSettings', JSON.stringify(store));
        } catch (e) { console.error(`${TAG} settings save failed: ${e}`); }
        try {
            for (const key of ['showFigures', 'showDockButton']) {
                UI.setOption('user', 'Mod', `${MOD_ID}.${key}`, Number(this.data[key]));
            }
            Configuration.getUser?.().saveCheckpoint?.();
        } catch (e) { /* localStorage copy stands */ }
    }

    get showFigures() { return this.loadAll().showFigures; }
    set showFigures(v) { this.loadAll().showFigures = Boolean(v); this.save(); }
    get showDockButton() { return this.loadAll().showDockButton; }
    set showDockButton(v) { this.loadAll().showDockButton = Boolean(v); this.save(); }

    getCollapsedLanes() { return [...(this.loadAll().collapsedLanes ?? [])]; }
    setCollapsedLanes(lanes) { this.loadAll().collapsedLanes = [...lanes]; this.save(); }
};

// ⚠ The stock Options.addInitCallback only queues for the FIRST init of the options
// model — a late-loading mod's options silently never appear (and re-opening the
// screen replays only the re-init list). ETFI's shipped fix: queue on BOTH lists.
try {
    if (Array.isArray(Options.optionsInitCallbacks) && Array.isArray(Options.optionsReInitCallbacks)) {
        Options.addInitCallback = function (callback) {
            if (this.optionsReInitCallbacks.length && !this.optionsInitCallbacks.length) {
                throw new Error("Options already initialized, cannot add init callback");
            }
            this.optionsInitCallbacks.push(callback);
            this.optionsReInitCallbacks.push(callback);
        };
    }
} catch (e) { console.error(`${TAG} options init patch failed: ${e}`); }

Options.addInitCallback(() => {
    Options.addOption({
        category: CategoryType.Mods,
        group: 'ma_bonus_dashboard',
        type: OptionType.Checkbox,
        id: 'mad-show-figures',
        initListener: (info) => { info.currentValue = MadSettings.showFigures; },
        updateListener: (_info, value) => { MadSettings.showFigures = value; },
        label: 'LOC_MAD_OPT_FIGURES',
        description: 'LOC_MAD_OPT_FIGURES_DESC',
    });
    Options.addOption({
        category: CategoryType.Mods,
        group: 'ma_bonus_dashboard',
        type: OptionType.Checkbox,
        id: 'mad-show-dock-button',
        initListener: (info) => { info.currentValue = MadSettings.showDockButton; },
        updateListener: (_info, value) => { MadSettings.showDockButton = value; },
        label: 'LOC_MAD_OPT_DOCK',
        description: 'LOC_MAD_OPT_DOCK_DESC',
    });
});

export { MadSettings as default };
