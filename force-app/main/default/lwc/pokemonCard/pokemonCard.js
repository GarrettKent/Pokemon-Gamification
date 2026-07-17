/* Title: pokemonCard
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Render ONE Pokemon (sprite, dex, types, level, rarity, stats) and its trainer actions — rename, power-up, release. Server-authoritative via pokemonGameController; no LSC dependency.
 * Modified: Garrett Kent - 06/21/2026 - Added Use Stone evolution affordance and shared white-out evolution animation.
 * Modified: Garrett Kent - 06/22/2026 - Use real packaged stone sprites on Use Stone buttons (stoneIconUrl), dropped the CSS dot color.
 * Modified: Garrett Kent - 06/22/2026 - Added Shiny/Dusk/Dawn evolution stones
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToast, ShowError, CheckBlank, isSuccess } from 'c/pokemonBasics';
import { getSeedSpecies, typeChipStyle, formatDex, capitalize, stoneIconUrl, PLACEHOLDER_SPRITE } from 'c/pokemonApiService';

import RenamePokemon from '@salesforce/apex/pokemonGameController.RenamePokemon';
import PowerUpPokemon from '@salesforce/apex/pokemonGameController.PowerUpPokemon';
import ReleasePokemon from '@salesforce/apex/pokemonGameController.ReleasePokemon';
import EvolvePokemon from '@salesforce/apex/pokemonGameController.EvolvePokemon';
import EvolveWithStone from '@salesforce/apex/pokemonGameController.EvolveWithStone';

// The sold stones — maps the species seed-item-name to its canonical stone key and button label.
const SOLD_STONES = [
    { seedName: 'fire-stone', stoneKey: 'firestone', label: 'Use Fire Stone' },
    { seedName: 'water-stone', stoneKey: 'waterstone', label: 'Use Water Stone' },
    { seedName: 'thunder-stone', stoneKey: 'thunderstone', label: 'Use Thunder Stone' },
    { seedName: 'leaf-stone', stoneKey: 'leafstone', label: 'Use Leaf Stone' },
    { seedName: 'moon-stone', stoneKey: 'moonstone', label: 'Use Moon Stone' },
    { seedName: 'shiny-stone', stoneKey: 'shinystone', label: 'Use Shiny Stone' },
    { seedName: 'dusk-stone', stoneKey: 'duskstone', label: 'Use Dusk Stone' },
    { seedName: 'dawn-stone', stoneKey: 'dawnstone', label: 'Use Dawn Stone' }
];

export default class PokemonCard extends LightningElement {
    @api availableTokens = 0;

    @track clientObj = {
        nicknameDraft: '',
        tokenDraft: 0,
        showReleaseModal: false,
        spendHint: 'Spend 0 XP',
        usableStones: [],
        hasUsableStone: false,
        isEvolving: false,
        evolvingClass: '',
        evolveMessage: ''
    };

    _pokemon;
    _availableStones;
    nicknameDirty = false;
    evolveStage = '';
    pendingEvolution = null;

    loading = false;
    debug = false;

    // @api setter runs on every parent re-pass of the value — recompute display so name/level/stats stay fresh after Give EXP/evolve reloads.
    @api
    get pokemon(){
        return this._pokemon;
    }
    set pokemon(value){
        this._pokemon = value;
        this.computeDisplay();
    }

    // @api setter — re-derive the usable-stone buttons whenever the parent re-passes new stone counts (e.g. after a purchase).
    @api
    get availableStones(){
        return this._availableStones;
    }
    set availableStones(value){
        this._availableStones = value;
        this.computeDisplay();
    }

    computeDisplay = () => {
        const pokemon = this._pokemon;
        if(CheckBlank(pokemon)) return;
        const displayName = pokemon.Nickname__c || pokemon.Species_Name__c;
        this.clientObj = {
            ...this.clientObj,
            dexLabel: formatDex(pokemon.Pokedex_Number__c),
            displayName,
            typeStyle1: typeChipStyle(pokemon.Type__c),
            type1Label: capitalize(pokemon.Type__c),
            typeStyle2: pokemon.Type_2__c ? typeChipStyle(pokemon.Type_2__c) : '',
            type2Label: pokemon.Type_2__c ? capitalize(pokemon.Type_2__c) : '',
            hasType2: !CheckBlank(pokemon.Type_2__c),
            isShiny: pokemon.Is_Shiny__c,
            isTraded: pokemon.Is_Traded__c,
            canRename: !pokemon.Is_Traded__c,
            levelLabel: `Lv. ${pokemon.Level__c}`,
            spriteAlt: displayName ? `${displayName} sprite` : 'Pokemon sprite',
            statRows: this.buildStatRows(pokemon),
            isLegendary: false,
            isMythical: false,
            canEvolveNow: false
        };
        // Only seed the nickname draft when the user has not started editing — never stomp an in-progress draft.
        if(!this.nicknameDirty){
            this.clientObj = { ...this.clientObj, nicknameDraft: pokemon.Nickname__c || '' };
        }
        getSeedSpecies(pokemon.Pokedex_Number__c).then(species => {
            const evolveLevel = species && species.evolveLevel;
            const canEvolveNow = !!(pokemon.Can_Evolve__c && evolveLevel && Number(pokemon.Level__c) >= Number(evolveLevel));
            const usableStones = this.buildUsableStones(species);
            this.clientObj = {
                ...this.clientObj,
                isLegendary: species.isLegendary,
                isMythical: species.isMythical,
                canEvolveNow,
                usableStones,
                hasUsableStone: usableStones.length > 0
            };
        }).catch(error => {
            if(this.debug) console.error('getSeedSpecies error:', error);
        });
    };

    // For each sold stone the species can evolve with AND the trainer owns, build a button row.
    buildUsableStones = (species) => {
        const stoneEvolutions = species && species.stoneEvolutions;
        if(CheckBlank(stoneEvolutions)) return [];
        const stones = this._availableStones || {};
        const usable = [];
        SOLD_STONES.forEach(stone => {
            const count = Number(stones[stone.stoneKey]) || 0;
            if(stoneEvolutions[stone.seedName] && count > 0){
                usable.push({
                    stoneKey: stone.stoneKey,
                    label: stone.label,
                    count,
                    iconUrl: stoneIconUrl(stone.stoneKey)
                });
            }
        });
        return usable;
    };

    buildStatRows = (pokemon) => {
        const rows = [
            { key: 'hp', label: 'HP', value: pokemon.HP__c },
            { key: 'atk', label: 'Atk', value: pokemon.Attack__c },
            { key: 'def', label: 'Def', value: pokemon.Defense__c },
            { key: 'spa', label: 'SpA', value: pokemon.Special_Attack__c },
            { key: 'spd', label: 'SpD', value: pokemon.Special_Defense__c },
            { key: 'spe', label: 'Spe', value: pokemon.Speed__c }
        ];
        return rows.map(row => {
            const rawValue = Number(row.value) || 0;
            const percent = Math.min(100, Math.round((rawValue / 255) * 100));
            return {
                ...row,
                value: rawValue,
                percent,
                barStyle: `width: ${percent}%;`
            };
        });
    };

    handleImageError = (event) => {
        event.target.src = PLACEHOLDER_SPRITE;
    };

    handleNicknameChange = (event) => {
        this.nicknameDirty = true;
        this.clientObj = { ...this.clientObj, nicknameDraft: event.target.value };
    };

    handleTokenChange = (event) => {
        const tokenDraft = event.target.value;
        const tokens = Number(tokenDraft) || 0;
        this.clientObj = { ...this.clientObj, tokenDraft, spendHint: `Spend ${tokens} XP` };
    };

    handleRename = () => {
        if(CheckBlank(this._pokemon)) return;
        const nickname = this.clientObj.nicknameDraft;
        if(CheckBlank(nickname)) return ShowToast('Rename', 'Enter a nickname first.', 'warning');
        this.loading = true;
        RenamePokemon({ params: { pokemonId: this._pokemon.Id, nickname } }).then(result => {
            if(!isSuccess(result)) return;
            ShowToast('Renamed', result.message, 'success');
            const renamed = result.pokemon || {};
            this.nicknameDirty = false;
            this.clientObj = {
                ...this.clientObj,
                displayName: renamed.Nickname__c || renamed.Species_Name__c || this.clientObj.displayName,
                nicknameDraft: renamed.Nickname__c || ''
            };
            this.dispatchEvent(new CustomEvent('pokemonupdated', { detail: { pokemon: result.pokemon } }));
        }).catch(ShowError).finally(() => {
            this.loading = false;
        });
    };

    handlePowerUp = () => {
        if(CheckBlank(this._pokemon)) return;
        const tokensToSpend = parseInt(this.clientObj.tokenDraft, 10) || 0;
        if(tokensToSpend <= 0) return ShowToast('Give EXP', 'Enter how many XP tokens to spend.', 'warning');
        if(tokensToSpend > Number(this.availableTokens)) return ShowToast('Give EXP', 'You do not have that many XP tokens.', 'warning');
        this.loading = true;
        PowerUpPokemon({ params: { pokemonId: this._pokemon.Id, tokensToSpend } }).then(result => {
            if(!isSuccess(result)) return;
            ShowToast('Give EXP', result.message, 'success');
            this.dispatchEvent(new CustomEvent('pokemonupdated', { detail: { pokemon: result.pokemon } }));
            this.dispatchEvent(new CustomEvent('balancechanged', { detail: { trainer: result.trainer } }));
        }).catch(ShowError).finally(() => {
            this.loading = false;
        });
    };

    handleEvolve = () => {
        if(CheckBlank(this._pokemon)) return;
        this.loading = true;
        EvolvePokemon({ params: { pokemonId: this._pokemon.Id } }).then(result => {
            if(!isSuccess(result)) return;
            this.playEvolution(result);
        }).catch(ShowError).finally(() => {
            this.loading = false;
        });
    };

    handleUseStone = (event) => {
        if(CheckBlank(this._pokemon)) return;
        const stone = event.currentTarget.dataset.stone;
        this.loading = true;
        EvolveWithStone({ params: { pokemonId: this._pokemon.Id, stone } }).then(result => {
            if(!isSuccess(result)) return;
            this.playEvolution(result);
        }).catch(ShowError).finally(() => {
            this.loading = false;
        });
    };

    // Shared evolution flow for both level-up and stone evolutions: white-out -> swap sprite -> reveal -> notify parent.
    playEvolution = (result) => {
        const evolved = result.pokemon;
        const oldName = this.clientObj.displayName;
        const newName = evolved.Species_Name__c;
        this.pendingEvolution = { evolved, oldName, newName, trainer: result.trainer };
        this.evolveStage = 'whiteout';
        this.clientObj = {
            ...this.clientObj,
            isEvolving: true,
            evolvingClass: 'evo-whiteout',
            evolveMessage: ''
        };
    };

    handleEvoAnimationEnd = () => {
        const pending = this.pendingEvolution;
        if(CheckBlank(pending)) return;
        if(this.evolveStage === 'whiteout'){
            this._pokemon = pending.evolved;
            this.computeDisplay();
            this.evolveStage = 'reveal';
            this.clientObj = {
                ...this.clientObj,
                evolvingClass: 'evo-reveal',
                evolveMessage: `Congratulations! Your ${pending.oldName} evolved into ${pending.newName}!`
            };
            return;
        }
        if(this.evolveStage === 'reveal'){
            this.evolveStage = '';
            this.clientObj = {
                ...this.clientObj,
                isEvolving: false,
                evolvingClass: '',
                evolveMessage: ''
            };
            this.dispatchEvent(new CustomEvent('pokemonupdated', { detail: { pokemon: pending.evolved } }));
            if(pending.trainer){
                this.dispatchEvent(new CustomEvent('balancechanged', { detail: { trainer: pending.trainer } }));
            }
            this.pendingEvolution = null;
        }
    };

    handleOpenRelease = () => {
        this.clientObj = { ...this.clientObj, showReleaseModal: true };
    };

    handleCancelRelease = () => {
        this.clientObj = { ...this.clientObj, showReleaseModal: false };
    };

    handleConfirmRelease = () => {
        if(CheckBlank(this._pokemon)) return;
        this.loading = true;
        ReleasePokemon({ params: { pokemonId: this._pokemon.Id } }).then(result => {
            if(!isSuccess(result)) return;
            ShowToast('Released', result.message, 'success');
            this.clientObj = { ...this.clientObj, showReleaseModal: false };
            this.dispatchEvent(new CustomEvent('pokemonreleased', { detail: { trainerId: result.trainerId } }));
        }).catch(ShowError).finally(() => {
            this.loading = false;
        });
    };
}
