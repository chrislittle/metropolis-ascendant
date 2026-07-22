/**
 * Metropolis Ascendant — Surveyor selected-unit portrait fix (issue #12 cosmetic follow-up).
 *
 * The selected-unit panel portrait is a LIVE 3D render: unit-actions.js setupUnitInfo() calls
 * WorldUI.requestPortrait(unitType, unitType, bg) and sets background-image url("live:/<UnitType>").
 * UNIT_MA_SURVEYOR has no art asset of its own, so that square renders BLACK even though the
 * VisualRemap gives it the donor model on the map and in the build menu.
 *
 * Fix: after the base setupUnitInfo() writes "live:/UNIT_MA_SURVEYOR", re-issue the request for
 * the donor and point the CSS at "live:/<donor>" — bit-for-bit the call path a real selected
 * donor unit uses, so it renders wherever that unit's portrait renders. Cosmetic-only and
 * fail-safe: any error leaves the base behavior (the black square), never breaks the panel.
 *
 * Donor MUST match $surveyorDonor in tools/gen-ascendant.ps1 (the VisualRemap donor).
 * 2026-07-13: Settler donor tried and rejected (Chris) - the Migrant stays.
 */

const MA_SURVEYOR = 'UNIT_MA_SURVEYOR';
const MA_SURVEYOR_DONOR = 'UNIT_MIGRANT';

class MadSurveyorPortraitDecorator {
    constructor(component) {
        try {
            const base = component.setupUnitInfo?.bind(component);
            if (!base) return;
            component.setupUnitInfo = function (...args) {
                const out = base(...args);
                try {
                    const img = component.portraitImage;
                    const bg = img?.style?.backgroundImage;
                    if (bg && bg.indexOf(MA_SURVEYOR) !== -1) {
                        WorldUI.requestPortrait(MA_SURVEYOR_DONOR, MA_SURVEYOR_DONOR, 'UnitPortraitsBG_BASE');
                        img.style.backgroundImage = `url("live:/${MA_SURVEYOR_DONOR}")`;
                    }
                }
                catch (e) {
                    console.error(`[metropolis-ascendant] surveyor-portrait swap failed: ${e}`);
                }
                return out;
            };
        }
        catch (e) {
            console.error(`[metropolis-ascendant] surveyor-portrait decorate failed: ${e}`);
        }
    }

    beforeAttach() {
    }

    afterAttach() {
    }

    beforeDetach() {
    }

    afterDetach() {
    }
}

Controls.decorate('unit-actions', (component) => new MadSurveyorPortraitDecorator(component));
