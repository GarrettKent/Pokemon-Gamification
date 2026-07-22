/* Title: biomeExplorer
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Biome exploration screen — the trainer picks a biome, the server returns tall-grass patches, and clicking a patch opens the wild encounter modal. Re-fetches the trainer after each outcome and bubbles balance changes to the dashboard.
 * Modified: Garrett Kent - 07/05/2026 - Patches now carry only an encrypted token + shiny flag; clicking grass reveals the encounter server-side, and the golden glow marks shiny (not rare) patches
 * Modified: Garrett Kent - 07/22/2026 - Pre-rolled biomes: all six biomes roll once at load and are cached, so switching between biomes never re-rolls the grass — only a page refresh does
 */
import { LightningElement, track } from 'lwc';
import { ShowToast, ShowError, CheckBlank, isSuccess } from 'c/pokemonBasics';
import { capitalize, ballIconUrl } from 'c/pokemonApiService';

import TALL_GRASS from '@salesforce/resourceUrl/tallGrassSway';

import GetMyTrainer from '@salesforce/apex/pokemonGameController.GetMyTrainer';
import GetBiomePokemon from '@salesforce/apex/pokemonGameController.GetBiomePokemon';
import RevealEncounter from '@salesforce/apex/pokemonGameController.RevealEncounter';

const GRASS_BACKGROUND_STYLE = `background-image: url(${TALL_GRASS}); background-size: cover; background-position: center;`;

export default class BiomeExplorer extends LightningElement {
    @track clientObj = {
        trainer: {},
        hasTrainer: false,
        ballCounts: { pokeball: 0, greatball: 0, ultraball: 0, masterball: 0 },
        selectedBiome: '',
        biomeTiles: [],
        biomeData: {},
        patches: [],
        hasPatches: false,
        displayPatches: [],
        backgroundImageUrl: '',
        showEncounter: false,
        encounter: null,
        activePatchIndex: null,
        ballPouch: []
    };
    loading = false;
    debug = false;
    _biomeRequests = {};

    biomes = [
        { value: 'Verdant_Meadow', label: 'Verdant Meadow' },
        { value: 'Rocky_Cavern', label: 'Rocky Cavern' },
        { value: 'Azure_Shore', label: 'Azure Shore' },
        { value: 'Mystic_Mirage', label: 'Mystic Mirage' },
        { value: 'Scorched_Summit', label: 'Scorched Summit' },
        { value: 'Spectral_Graveyard', label: 'Spectral Graveyard' }
    ];

    connectedCallback(){
        this.clientObj = { ...this.clientObj, biomeTiles: this.buildBiomeTiles('') };
        this.loadTrainer();
    }

    buildBallPouch = (trainer) => {
        const safe = trainer || {};
        return [
            { key: 'poke', icon: ballIconUrl('poke'), count: safe.Poke_Balls__c || 0, alt: 'Poke Balls' },
            { key: 'great', icon: ballIconUrl('great'), count: safe.Great_Balls__c || 0, alt: 'Great Balls' },
            { key: 'ultra', icon: ballIconUrl('ultra'), count: safe.Ultra_Balls__c || 0, alt: 'Ultra Balls' },
            { key: 'master', icon: ballIconUrl('master'), count: safe.Master_Balls__c || 0, alt: 'Master Balls' }
        ];
    };

    hasTrainerValue = (trainer) => !CheckBlank(trainer) && !CheckBlank(trainer.Id);

    buildBallCounts = (trainer) => {
        const safe = trainer || {};
        return {
            pokeball: safe.Poke_Balls__c || 0,
            greatball: safe.Great_Balls__c || 0,
            ultraball: safe.Ultra_Balls__c || 0,
            masterball: safe.Master_Balls__c || 0
        };
    };

    buildBiomeTiles = (selectedBiome) => {
        return this.biomes.map(biome => {
            const selected = biome.value === selectedBiome;
            return {
                ...biome,
                selected,
                tileClass: selected
                    ? 'slds-button slds-button_brand slds-button_stretch'
                    : 'slds-button slds-button_neutral slds-button_stretch'
            };
        });
    };

    buildDisplayPatches = (patches) => {
        return (patches || []).map((patch, index) => {
            const consumed = !!patch.consumed;
            const isShiny = !!patch.isShiny;
            const grassClass = isShiny && !consumed ? 'patch-tile patch-tile_grass patch-tile_shiny' : 'patch-tile patch-tile_grass';
            return {
                ...patch,
                index,
                consumed,
                grassClass,
                style: consumed ? '' : GRASS_BACKGROUND_STYLE
            };
        });
    };

    loadTrainer = () => {
        this.loading = true;
        GetMyTrainer({ params: { includePokemon: false } }).then(result => {
            if(result.status === 'error') return ShowToast('ERROR', result.message, 'error');
            if(result.status === 'warning') ShowToast('Heads up', result.message, 'warning');
            const trainer = result.trainer || {};
            this.clientObj = {
                ...this.clientObj,
                trainer,
                hasTrainer: this.hasTrainerValue(trainer),
                ballCounts: this.buildBallCounts(trainer),
                ballPouch: this.buildBallPouch(trainer)
            };
            if(this.clientObj.hasTrainer) this.prefetchBiomes();
        }).catch(error => {
            if(this.debug) console.log(`loadTrainer error: ${JSON.stringify(error)}`);
            ShowError(error);
        }).finally(() => {
            this.loading = false;
        });
    };

    // Roll every biome once up front — what hides in the grass is decided at page load. A failed roll stays
    // silent here (six error toasts would spam the load) and simply retries when the trainer clicks that biome.
    prefetchBiomes = () => {
        this.biomes.forEach(biome => this.fetchBiomePatches(biome.value).catch(() => {}));
    };

    // One roll per biome per page load: the first request (prefetch or click) creates the promise and every
    // later request reuses it, so switching between biomes can never re-roll. Failures clear their slot to allow a retry.
    fetchBiomePatches = (biome) => {
        if(this._biomeRequests[biome]) return this._biomeRequests[biome];
        this._biomeRequests[biome] = GetBiomePokemon({ params: { biome } }).then(result => {
            if(result.status === 'error') throw new Error(result.message);
            if(result.status === 'warning') ShowToast('Heads up', result.message, 'warning');
            const entry = { patches: result.patches || [], backgroundImageUrl: result.backgroundImageUrl || '' };
            this.clientObj = { ...this.clientObj, biomeData: { ...this.clientObj.biomeData, [biome]: entry } };
            return entry;
        }).catch(error => {
            delete this._biomeRequests[biome];
            throw error;
        });
        return this._biomeRequests[biome];
    };

    selectBiome = (event) => {
        const biome = event.currentTarget.dataset.biome;
        if(CheckBlank(biome)) return;
        this.clientObj = { ...this.clientObj, selectedBiome: biome, biomeTiles: this.buildBiomeTiles(biome) };
        const cachedEntry = this.clientObj.biomeData[biome];
        if(cachedEntry) return this.applyBiomeEntry(cachedEntry);
        this.loading = true;
        this.fetchBiomePatches(biome).then(entry => {
            if(this.clientObj.selectedBiome === biome) this.applyBiomeEntry(entry);
        }).catch(error => {
            if(this.debug) console.log(`selectBiome error: ${JSON.stringify(error)}`);
            ShowError(error);
        }).finally(() => {
            this.loading = false;
        });
    };

    applyBiomeEntry = (entry) => {
        const patches = entry.patches || [];
        this.clientObj = {
            ...this.clientObj,
            patches,
            hasPatches: patches.length > 0,
            displayPatches: this.buildDisplayPatches(patches),
            backgroundImageUrl: entry.backgroundImageUrl || ''
        };
    };

    // The patch only holds an encrypted token — the server reveals what is hiding in the grass on click,
    // so the wild Pokemon cannot be inspected (or edited) in dev tools before the rustle.
    openEncounter = (event) => {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const patch = this.clientObj.patches[index];
        if(CheckBlank(patch) || patch.consumed) return;
        this.loading = true;
        RevealEncounter({ params: { token: patch.token } }).then(result => {
            if(result.status === 'error') return ShowToast('ERROR', result.message, 'error');
            if(result.status === 'warning') return ShowToast('Heads up', result.message, 'warning');
            this.clientObj = {
                ...this.clientObj,
                encounter: {
                    token: patch.token,
                    dex: result.dex,
                    name: capitalize(result.name),
                    image: result.image,
                    type1: result.type1,
                    type2: result.type2,
                    level: result.level,
                    isShiny: result.isShiny
                },
                activePatchIndex: index,
                showEncounter: true
            };
        }).catch(error => {
            if(this.debug) console.log(`openEncounter error: ${JSON.stringify(error)}`);
            ShowError(error);
        }).finally(() => {
            this.loading = false;
        });
    };

    handleCaught = (event) => {
        const isShiny = event.detail.isShiny;
        // Master Ball milestone grant disabled 07/22/2026:
        // const masterBallsGranted = event.detail.masterBallsGranted || 0;
        this.consumeActivePatch();
        const pokemonName = this.clientObj.encounter ? this.clientObj.encounter.name : 'Pokemon';
        if(isShiny) ShowToast('Gotcha!', `A shiny ${pokemonName} was caught! Incredible!`, 'success');
        else ShowToast('Gotcha!', `${pokemonName} was caught!`, 'success');
        // if(masterBallsGranted > 0) ShowToast('Bonus!', `You earned ${masterBallsGranted} Master Ball(s)!`, 'success');
        this.refreshAfterOutcome();
    };

    handleFled = () => {
        const pokemonName = this.clientObj.encounter ? this.clientObj.encounter.name : 'Pokemon';
        this.consumeActivePatch();
        this.clientObj = { ...this.clientObj, showEncounter: false, encounter: null };
        ShowToast('It fled!', `The wild ${pokemonName} fled! That patch is now empty.`, 'warning');
        this.refreshAfterOutcome();
    };

    // Broke free: keep the encounter open (the trainer throws again) and the patch unconsumed; just sync ball/balance counts.
    handleBrokeFree = () => {
        this.refreshAfterOutcome();
    };

    handleClose = () => {
        this.clientObj = { ...this.clientObj, showEncounter: false, encounter: null };
    };

    consumeActivePatch = () => {
        const activeIndex = this.clientObj.activePatchIndex;
        if(activeIndex === undefined || activeIndex === null) return;
        const patches = this.clientObj.patches.map((patch, index) =>
            index === activeIndex ? { ...patch, consumed: true } : patch
        );
        // Write the consumed patch back into the biome cache too, so a searched patch stays searched when the trainer switches biomes and returns.
        const selectedBiome = this.clientObj.selectedBiome;
        const cachedEntry = this.clientObj.biomeData[selectedBiome];
        const biomeData = cachedEntry
            ? { ...this.clientObj.biomeData, [selectedBiome]: { ...cachedEntry, patches } }
            : this.clientObj.biomeData;
        this.clientObj = {
            ...this.clientObj,
            patches,
            biomeData,
            hasPatches: patches.length > 0,
            displayPatches: this.buildDisplayPatches(patches)
        };
    };

    // Refresh balances after a throw. The modal stays open on a catch (Done) or a broke-free (throw again);
    // only handleFled closes it. The trainer dismisses a catch themselves via handleClose.
    refreshAfterOutcome = () => {
        GetMyTrainer({ params: { includePokemon: false } }).then(result => {
            if(!isSuccess(result)) return;
            const trainer = result.trainer || {};
            this.clientObj = {
                ...this.clientObj,
                trainer,
                hasTrainer: this.hasTrainerValue(trainer),
                ballCounts: this.buildBallCounts(trainer),
                ballPouch: this.buildBallPouch(trainer)
            };
            this.dispatchEvent(new CustomEvent('balancechanged', { detail: { trainer: result.trainer } }));
        }).catch(error => {
            if(this.debug) console.log(`refreshAfterOutcome error: ${JSON.stringify(error)}`);
            ShowError(error);
        });
    };
}
