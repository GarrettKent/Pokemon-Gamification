/* Title: trainerDashboard
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Trainer Hub — default landing page. Renders a Trainer Card header and a roster of pokemonCard
 *          components, or hosts the Professor Oak onboarding flow when the user has no trainer yet.
 * Modified: Garrett Kent - 06/21/2026 - Added client-side roster search/filter/sort/pagination over the loaded party.
 * Modified: Garrett Kent - 06/21/2026 - Derived availableStones from the trainer and passed it down to each pokemonCard for stone evolution.
 * Modified: Garrett Kent - 06/22/2026 - Roster markup: equal-height CSS-grid tiles, regrouped pagination footer, page-size combobox auto alignment.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowError, CheckBlank, isSuccess } from 'c/pokemonBasics';
import { ballIconUrl } from 'c/pokemonApiService';
import GetMyTrainer from '@salesforce/apex/pokemonGameController.GetMyTrainer';
import GetTrainer from '@salesforce/apex/pokemonGameController.GetTrainer';

export default class TrainerDashboard extends LightningElement {
    @api recordId;
    @track clientObj = {
        trainer: null,
        party: [],
        rivalName: '',
        showOnboarding: false,
        headerBadges: [],
        ballSummary: [],
        availableTokens: 0,
        availableStones: { firestone: 0, waterstone: 0, thunderstone: 0, leafstone: 0, moonstone: 0 },
        partyCount: 0,
        hasParty: false,
        hasRival: false,
        rivalLabel: 'Rival: ',
        rosterHeading: 'Your Pokemon — 0',
        showFilters: false,
        pageItems: [],
        typeOptions: [],
        sortOptions: [],
        sortDirectionOptions: [],
        pageSizeOptions: [],
        pageSizeValue: '10',
        pageInfo: '',
        pageLabel: '',
        isFirstPage: true,
        isLastPage: true,
        hasResults: false,
        noMatches: false
    };
    loading = false;
    debug = false;

    searchTerm = '';
    selectedTypes = [];
    minLevel = '';
    maxLevel = '';
    shinyOnly = false;
    sortField = 'Level__c';
    sortDirection = 'desc';
    pageSize = 10;
    pageNumber = 1;

    starterIds = '1,4,7,152,155,158,252,255,258,387,390,393,25,133,447,129,63';

    connectedCallback() {
        this.load();
    }

    // Derive the display values from trainer/party/rivalName once, at each point those inputs change.
    buildDerived = (trainer, party, rivalName) => {
        const partyCount = party ? party.length : 0;
        return {
            availableTokens: trainer ? trainer.Experience_Tokens__c : 0,
            partyCount,
            hasParty: partyCount > 0,
            hasRival: !CheckBlank(rivalName),
            rivalLabel: `Rival: ${rivalName}`,
            rosterHeading: `Your Pokemon — ${partyCount}`
        };
    };

    buildBadges = (trainer) => {
        const safe = trainer || {};
        const headerBadges = [
            { key: 'currency', label: `₽ ${safe.Currency__c || 0}`, iconName: 'utility:moneybag' },
            { key: 'xp', label: `XP ${safe.Experience_Tokens__c || 0}`, iconName: 'utility:trending' }
        ];
        const ballSummary = [
            { key: 'poke', label: `Poke Balls ${safe.Poke_Balls__c || 0}`, icon: ballIconUrl('poke') },
            { key: 'great', label: `Great Balls ${safe.Great_Balls__c || 0}`, icon: ballIconUrl('great') },
            { key: 'ultra', label: `Ultra Balls ${safe.Ultra_Balls__c || 0}`, icon: ballIconUrl('ultra') },
            { key: 'master', label: `Master Balls ${safe.Master_Balls__c || 0}`, icon: ballIconUrl('master') }
        ];
        return { headerBadges, ballSummary };
    };

    // Derive the trainer's sold-stone counts into the canonical {stoneKey: count} shape pokemonCard expects.
    buildStones = (trainer) => ({
        firestone: (trainer && trainer.Fire_Stones__c) || 0,
        waterstone: (trainer && trainer.Water_Stones__c) || 0,
        thunderstone: (trainer && trainer.Thunder_Stones__c) || 0,
        leafstone: (trainer && trainer.Leaf_Stones__c) || 0,
        moonstone: (trainer && trainer.Moon_Stones__c) || 0
    });

    // Derive the distinct type options present across the roster, guarding against null Type_2__c.
    buildTypeOptions = (party) => {
        const seen = {};
        const options = [];
        (party || []).forEach((poke) => {
            [poke.Type__c, poke.Type_2__c].forEach((type) => {
                if(!CheckBlank(type) && !seen[type]){
                    seen[type] = true;
                    options.push({ label: type, value: type });
                }
            });
        });
        return options.sort((first, second) => first.label.localeCompare(second.label));
    };

    matchesSearch = (poke, term) => {
        if(CheckBlank(term)) return true;
        const needle = term.toLowerCase();
        const species = (poke.Species_Name__c || '').toLowerCase();
        const nickname = (poke.Nickname__c || '').toLowerCase();
        const dexNumber = poke.Pokedex_Number__c == null ? '' : `${poke.Pokedex_Number__c}`;
        const dexPadded = dexNumber === '' ? '' : dexNumber.padStart(3, '0');
        return (
            species.includes(needle) ||
            nickname.includes(needle) ||
            (dexNumber !== '' && dexNumber.includes(needle)) ||
            (dexPadded !== '' && dexPadded.includes(needle))
        );
    };

    matchesTypes = (poke, types) => {
        if(!types || types.length === 0) return true;
        return types.some((type) => type === poke.Type__c || type === poke.Type_2__c);
    };

    matchesLevel = (poke, min, max) => {
        const level = poke.Level__c == null ? 0 : poke.Level__c;
        if(min !== null && level < min) return false;
        if(max !== null && level > max) return false;
        return true;
    };

    // Compare for sort with blank/null values always pushed to the end regardless of direction.
    compareForSort = (first, second, field, direction) => {
        const firstValue = first[field];
        const secondValue = second[field];
        const firstBlank = firstValue == null || firstValue === '';
        const secondBlank = secondValue == null || secondValue === '';
        if(firstBlank && secondBlank) return 0;
        if(firstBlank) return 1;
        if(secondBlank) return -1;
        let comparison = 0;
        if(typeof firstValue === 'number' && typeof secondValue === 'number'){
            comparison = firstValue - secondValue;
        }
        else{
            comparison = `${firstValue}`.localeCompare(`${secondValue}`);
        }
        return direction === 'desc' ? -comparison : comparison;
    };

    // Single source of truth: filter -> sort (nulls last) -> paginate the loaded party into the view.
    recomputeRoster = () => {
        const party = this.clientObj.party || [];
        const minLevelBound = CheckBlank(this.minLevel) || isNaN(Number(this.minLevel)) ? null : Number(this.minLevel);
        const maxLevelBound = CheckBlank(this.maxLevel) || isNaN(Number(this.maxLevel)) ? null : Number(this.maxLevel);

        const filtered = party.filter(
            (poke) =>
                this.matchesSearch(poke, this.searchTerm) &&
                this.matchesTypes(poke, this.selectedTypes) &&
                this.matchesLevel(poke, minLevelBound, maxLevelBound) &&
                (!this.shinyOnly || poke.Is_Shiny__c === true)
        );

        const sorted = [...filtered].sort((first, second) =>
            this.compareForSort(first, second, this.sortField, this.sortDirection)
        );

        const totalFiltered = sorted.length;
        const totalPages = totalFiltered === 0 ? 1 : Math.ceil(totalFiltered / this.pageSize);
        if(this.pageNumber > totalPages) this.pageNumber = totalPages;
        if(this.pageNumber < 1) this.pageNumber = 1;

        const startIndex = (this.pageNumber - 1) * this.pageSize;
        const pageItems = sorted.slice(startIndex, startIndex + this.pageSize);
        const firstShown = totalFiltered === 0 ? 0 : startIndex + 1;
        const lastShown = startIndex + pageItems.length;

        this.clientObj = {
            ...this.clientObj,
            pageItems,
            typeOptions: this.buildTypeOptions(party),
            sortOptions: [
                { label: 'Level', value: 'Level__c' },
                { label: 'Pokedex #', value: 'Pokedex_Number__c' },
                { label: 'Name', value: 'Species_Name__c' },
                { label: 'Nickname', value: 'Nickname__c' }
            ],
            sortDirectionOptions: [
                { label: 'Ascending', value: 'asc' },
                { label: 'Descending', value: 'desc' }
            ],
            pageSizeOptions: [
                { label: '5', value: '5' },
                { label: '10', value: '10' },
                { label: '25', value: '25' },
                { label: '50', value: '50' },
                { label: '100', value: '100' }
            ],
            pageSizeValue: `${this.pageSize}`,
            pageInfo: `Showing ${firstShown}-${lastShown} of ${totalFiltered}`,
            pageLabel: `Page ${this.pageNumber} of ${totalPages}`,
            isFirstPage: this.pageNumber <= 1,
            isLastPage: this.pageNumber >= totalPages,
            hasResults: totalFiltered > 0,
            noMatches: party.length > 0 && totalFiltered === 0
        };
    };

    load = () => {
        this.loading = true;
        const call = this.recordId
            ? GetTrainer({ params: { trainerId: this.recordId, includePokemon: true } })
            : GetMyTrainer({ params: { includePokemon: true } });
        call
            .then((result) => {
                if(!isSuccess(result)){
                    this.loading = false;
                    return;
                }
                if(!result.trainer){
                    this.clientObj = {
                        ...this.clientObj,
                        trainer: null,
                        party: [],
                        showOnboarding: true,
                        headerBadges: [],
                        ballSummary: [],
                        ...this.buildDerived(null, [], this.clientObj.rivalName)
                    };
                    this.recomputeRoster();
                    this.loading = false;
                    return;
                }
                const badges = this.buildBadges(result.trainer);
                const party = result.pokemon || [];
                this.clientObj = {
                    ...this.clientObj,
                    trainer: result.trainer,
                    party,
                    showOnboarding: false,
                    headerBadges: badges.headerBadges,
                    ballSummary: badges.ballSummary,
                    availableStones: this.buildStones(result.trainer),
                    ...this.buildDerived(result.trainer, party, this.clientObj.rivalName)
                };
                this.recomputeRoster();
                this.resolveRival();
                this.loading = false;
            })
            .catch(this.handleCatch);
    };

    resolveRival = () => {
        const rivalId = this.clientObj.trainer && this.clientObj.trainer.Rival__c;
        if(CheckBlank(rivalId)){
            this.clientObj = {
                ...this.clientObj,
                rivalName: '',
                ...this.buildDerived(this.clientObj.trainer, this.clientObj.party, '')
            };
            return;
        }
        GetTrainer({ params: { trainerId: rivalId, includePokemon: false } })
            .then((result) => {
                if(result.status === 'success' && result.trainer){
                    this.clientObj = {
                        ...this.clientObj,
                        rivalName: result.trainer.Name,
                        ...this.buildDerived(this.clientObj.trainer, this.clientObj.party, result.trainer.Name)
                    };
                }
            })
            .catch(() => {});
    };

    handleSearchChange = (event) => {
        this.searchTerm = event.target.value || '';
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleToggleFilters = () => {
        this.clientObj = { ...this.clientObj, showFilters: !this.clientObj.showFilters };
    };

    handleTypesChange = (event) => {
        this.selectedTypes = event.detail.value || [];
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleMinLevelChange = (event) => {
        this.minLevel = event.target.value;
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleMaxLevelChange = (event) => {
        this.maxLevel = event.target.value;
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleShinyChange = (event) => {
        this.shinyOnly = event.target.checked;
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleClearFilters = () => {
        this.searchTerm = '';
        this.selectedTypes = [];
        this.minLevel = '';
        this.maxLevel = '';
        this.shinyOnly = false;
        this.sortField = 'Level__c';
        this.sortDirection = 'desc';
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleSortFieldChange = (event) => {
        this.sortField = event.detail.value;
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleSortDirectionChange = (event) => {
        this.sortDirection = event.detail.value;
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handlePageSizeChange = (event) => {
        this.pageSize = Number(event.detail.value);
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handleFirstPage = () => {
        this.pageNumber = 1;
        this.recomputeRoster();
    };

    handlePreviousPage = () => {
        this.pageNumber = this.pageNumber - 1;
        this.recomputeRoster();
    };

    handleNextPage = () => {
        this.pageNumber = this.pageNumber + 1;
        this.recomputeRoster();
    };

    handleLastPage = () => {
        // recomputeRoster clamps an over-large page down to the last valid page of the filtered set.
        this.pageNumber = Number.MAX_SAFE_INTEGER;
        this.recomputeRoster();
    };

    handleStartAdventure = () => {
        this.clientObj = { ...this.clientObj, showOnboarding: true };
    };

    handleOnboardingClosed = () => {
        this.clientObj = { ...this.clientObj, showOnboarding: false };
    };

    handleTrainerCreated = () => {
        this.load();
    };

    handleBalanceChanged = (event) => {
        const badges = this.buildBadges(event.detail.trainer);
        this.clientObj = {
            ...this.clientObj,
            trainer: event.detail.trainer,
            headerBadges: badges.headerBadges,
            ballSummary: badges.ballSummary,
            availableStones: this.buildStones(event.detail.trainer),
            ...this.buildDerived(event.detail.trainer, this.clientObj.party, this.clientObj.rivalName)
        };
        this.resolveRival();
    };

    handleReleased = () => {
        this.load();
    };

    handleUpdated = () => {
        this.load();
    };

    handleCatch = (error) => {
        this.loading = false;
        ShowError(error);
    };
}
