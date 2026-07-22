/* Title: wildEncounterModal
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Wild Pokemon encounter modal — shows the wild Pokemon, lets the trainer pick a ball and throw it, animates the catch shake, and reports the server-derived outcome (caught / broke free / fled) to the host. On a broke-free the trainer can throw again; on a flee the host closes the modal. Owns the CatchPokemon call; the server alone derives capture rate, level, shiny, flee, and RNG.
 * Modified: Garrett Kent - 06/20/2026 - Pass the shown encounter level into CatchPokemon (server clamps it into the legal tier+anchor band)
 * Modified: Garrett Kent - 06/21/2026 - Capture juice: finite three-wobble (or one big Critical Capture wobble) driven off the server result, then a ball snap + Gotcha star-burst on a catch
 * Modified: Garrett Kent - 07/05/2026 - Throws send the encrypted encounter token instead of dex/level — the server already knows what is in the grass
 * Modified: Garrett Kent - 07/05/2026 - Battle-scene resize: bag rail replaces the footer ball buttons, the thrown ball takes the Pokemon's spot on the stage and wobbles (stars pop over the ball on a catch), and the footer throw spinner is gone
 * Modified: Garrett Kent - 07/22/2026 - Dropped masterBallsGranted from the caught event (the dex-milestone grant is gone; Master Balls are no longer obtainable)
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToast, ShowError, isSuccess } from 'c/pokemonBasics';
import { formatDex, typeChipStyle, PLACEHOLDER_SPRITE, ballIconUrl } from 'c/pokemonApiService';

import CatchPokemon from '@salesforce/apex/pokemonGameController.CatchPokemon';

const BALL_DEFS = [
    { key: 'pokeball', label: 'Poke Ball', title: 'Throw a Poke Ball' },
    { key: 'greatball', label: 'Great Ball', title: 'Throw a Great Ball' },
    { key: 'ultraball', label: 'Ultra Ball', title: 'Throw an Ultra Ball' },
    { key: 'masterball', label: 'Master Ball', title: 'Throw a Master Ball' }
];

export default class WildEncounterModal extends LightningElement {
    @track clientObj = {
        phase: 'choosingBall',
        shakeClass: '',
        snapClass: '',
        showBurst: false,
        dexDisplay: formatDex(0),
        type1Style: '',
        type2Style: '',
        hasSecondType: false,
        ballButtons: [],
        isChoosingBall: true,
        isCaught: false,
        brokeFree: false,
        showBall: false,
        thrownBallIcon: '',
        spriteSrc: '',
        railClass: 'ball-rail'
    };
    loading = false;
    debug = false;

    _encounter;
    _ballCounts;
    _pendingResult;

    @api
    get encounter(){
        return this._encounter;
    }
    set encounter(value){
        this._encounter = value;
        this.clientObj = {
            ...this.clientObj,
            dexDisplay: formatDex(value ? value.dex : 0),
            type1Style: value ? typeChipStyle(value.type1) : '',
            type2Style: value ? typeChipStyle(value.type2) : '',
            hasSecondType: !!(value && value.type2),
            spriteSrc: value ? value.image : ''
        };
    }

    @api
    get ballCounts(){
        return this._ballCounts;
    }
    set ballCounts(value){
        this._ballCounts = value;
        this.buildBallButtons();
    }

    buildBallButtons = () => {
        const ballButtons = BALL_DEFS.map(ball => {
            const count = this._ballCounts ? this._ballCounts[ball.key] || 0 : 0;
            return { ...ball, count, icon: ballIconUrl(ball.key), disabled: this.loading || count <= 0 };
        });
        this.clientObj = { ...this.clientObj, ballButtons };
    };

    buildPhaseFlags = (phase) => {
        this.clientObj = {
            ...this.clientObj,
            phase,
            isChoosingBall: phase === 'choosingBall' || phase === 'throwing',
            isCaught: phase === 'caught',
            showBall: phase === 'throwing' || phase === 'caught',
            // The rail stays mounted on a catch (hidden, width reserved) so the ball does not jump mid snap/burst.
            railClass: phase === 'caught' ? 'ball-rail ball-rail_hidden' : 'ball-rail'
        };
    };

    throwBall = (event) => {
        const ballType = event.currentTarget.dataset.ball;
        if(this._ballCounts[ballType] <= 0) return ShowToast('Out of balls', `You have no ${ballType} left.`, 'warning');
        this.loading = true;
        this._pendingResult = null;
        this.buildPhaseFlags('throwing');
        this.clientObj = { ...this.clientObj, shakeClass: 'pokemon-shake', snapClass: '', showBurst: false, brokeFree: false, thrownBallIcon: ballIconUrl(ballType) };
        this.buildBallButtons();
        CatchPokemon({ params: { token: this._encounter.token, ballType } }).then(result => {
            if(!isSuccess(result)){
                this.resetToChoosing();
                if(result && result.message) ShowToast('Heads up', result.message, 'warning');
                return;
            }
            // Hand the network result to the finite wobble; handleWobbleEnd applies the outcome once the rock settles.
            // Phase stays 'throwing' (loading stays true so the bag rail stays disabled) so the thrown ball keeps the stage until the wobble lands.
            this._pendingResult = result;
            const wobbleClass = result.caught && result.criticalCapture === true ? 'pokemon-crit-wobble' : 'pokemon-wobble';
            this.clientObj = { ...this.clientObj, shakeClass: wobbleClass };
        }).catch(error => {
            this.resetToChoosing();
            if(this.debug) console.log(`throwBall error: ${JSON.stringify(error)}`);
            ShowError(error);
        });
    };

    handleWobbleEnd = () => {
        const result = this._pendingResult;
        if(!result) return;
        this._pendingResult = null;
        this.clientObj = { ...this.clientObj, shakeClass: '' };
        if(result.caught){
            this.loading = false;
            this.buildPhaseFlags('caught');
            this.clientObj = { ...this.clientObj, snapClass: 'pokemon-snap', showBurst: true };
            // Master Ball milestone grant disabled 07/22/2026 — masterBallsGranted dropped from the caught event:
            // this.dispatchEvent(new CustomEvent('caught', { detail: { pokemon: result.pokemon, ballCounts: result.ballCounts, isShiny: result.isShiny, masterBallsGranted: result.masterBallsGranted } }));
            this.dispatchEvent(new CustomEvent('caught', { detail: { pokemon: result.pokemon, ballCounts: result.ballCounts, isShiny: result.isShiny } }));
            return;
        }
        if(result.fled){
            this.loading = false;
            this.dispatchEvent(new CustomEvent('fled', { detail: { ballCounts: result.ballCounts } }));
            return;
        }
        // Broke free: the ball pops open (phase flip hides it, the Pokemon returns), so reopen the bag rail with the decremented counts and let the trainer try again.
        this._ballCounts = result.ballCounts;
        this.loading = false;
        this.buildPhaseFlags('choosingBall');
        this.clientObj = { ...this.clientObj, brokeFree: true };
        this.buildBallButtons();
        this.dispatchEvent(new CustomEvent('brokefree', { detail: { ballCounts: result.ballCounts } }));
    };

    resetToChoosing = () => {
        this._pendingResult = null;
        this.loading = false;
        this.buildPhaseFlags('choosingBall');
        this.clientObj = { ...this.clientObj, shakeClass: '', snapClass: '', showBurst: false };
        this.buildBallButtons();
    };

    handleClose = () => {
        this.dispatchEvent(new CustomEvent('close'));
    };

    // Swap in clientObj (not on the DOM node) so the placeholder survives the sprite unmounting while the thrown ball has the stage.
    handleImageError = () => {
        this.clientObj = { ...this.clientObj, spriteSrc: PLACEHOLDER_SPRITE };
    };
}
