/* Title: professorOakOnboarding
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: First-run trainer wizard in Professor Oak's Lab. Collects trainer name, optional rival, and starter, then calls CreateTrainer and emits 'trainercreated'.
 * Modified: Garrett Kent - 06/21/2026 - De-AI the onboarding UI: swap slds-box panels for borderless elevated oak-panel/starter-tile styling.
 */
import { LightningElement, api, track } from 'lwc';
import { ShowToast, ShowError, CheckBlank } from 'c/pokemonBasics';
import { getSeedSpecies, buildArtworkUrl, typeChipStyle, capitalize, PLACEHOLDER_SPRITE } from 'c/pokemonApiService';
import OAK_IMAGE from '@salesforce/resourceUrl/professorOak';
import GetMyTrainer from '@salesforce/apex/pokemonGameController.GetMyTrainer';
import GetOtherTrainers from '@salesforce/apex/pokemonGameController.GetOtherTrainers';
import CreateTrainer from '@salesforce/apex/pokemonGameController.CreateTrainer';

export default class ProfessorOakOnboarding extends LightningElement {
    @api starterIds;

    oakImageUrl = OAK_IMAGE;

    @track clientObj = {
        step: 'welcome',
        trainerName: '',
        rivalTrainerId: '',
        selectedStarterId: null,
        starters: [],
        oakLine: 'Hello there! Welcome to the world of Pokemon!',
        isWelcome: true,
        isName: false,
        isRival: false,
        isStarter: false,
        isCreating: false,
        isDone: false,
        starterNotChosen: true,
        decoratedStarters: []
    };
    @track rivalOptions = [{ label: 'No rival', value: '' }];
    loading = false;
    debug = false;

    connectedCallback(){
        this.recomputeStepState();
        this.loading = true;
        GetMyTrainer({ params: { includePokemon: false } }).then(result => {
            if(result.status === 'success'){
                this.clientObj = { ...this.clientObj, trainerName: result.currentUserName || '' };
            }
            return this.loadStarters();
        }).then(() => {
            return GetOtherTrainers({ params: {} });
        }).then(result => {
            if(result.status === 'success' && result.otherTrainers){
                this.rivalOptions = [{ label: 'No rival', value: '' }, ...result.otherTrainers];
            }
            this.loading = false;
        }).catch(error => {
            this.loading = false;
            ShowError(error);
        });
    }

    loadStarters = () => {
        if(CheckBlank(this.starterIds)) return Promise.resolve();
        const dexList = this.starterIds.split(',').map(dex => dex.trim()).filter(dex => !CheckBlank(dex));
        return Promise.all(dexList.map(dex => this.buildStarter(Number(dex)))).then(starters => {
            this.clientObj = { ...this.clientObj, starters: starters.filter(starter => starter !== null) };
            this.recomputeStepState();
        });
    }

    buildStarter = (dex) => {
        return getSeedSpecies(dex).then(species => {
            if(!species) return null;
            return {
                id: Number(dex),
                name: capitalize(species.name),
                artworkUrl: species.image || buildArtworkUrl(dex),
                type1: species.type1,
                type2: species.type2,
                typeStyle1: typeChipStyle(species.type1),
                typeStyle2: species.type2 ? typeChipStyle(species.type2) : ''
            };
        }).catch(() => null);
    }

    // Derive the step flags, starter-chosen guard, and decorated starter cards from the current
    // step/selectedStarterId/starters. Called once at init and from every place those inputs change.
    recomputeStepState = () => {
        const step = this.clientObj.step;
        const selectedStarterId = this.clientObj.selectedStarterId;
        const decoratedStarters = this.clientObj.starters.map(starter => ({
            ...starter,
            selectedClass: starter.id === selectedStarterId
                ? 'starter-tile starter-tile_selected'
                : 'starter-tile'
        }));
        this.clientObj = {
            ...this.clientObj,
            isWelcome: step === 'welcome',
            isName: step === 'name',
            isRival: step === 'rival',
            isStarter: step === 'starter',
            isCreating: step === 'creating',
            isDone: step === 'done',
            starterNotChosen: CheckBlank(selectedStarterId),
            decoratedStarters
        };
    }

    handleNameChange = (event) => {
        this.clientObj = { ...this.clientObj, trainerName: event.target.value };
    }

    handleRivalChange = (event) => {
        this.clientObj = { ...this.clientObj, rivalTrainerId: event.detail.value };
    }

    handleStarterSelect = (event) => {
        const selectedStarterId = Number(event.currentTarget.dataset.id);
        this.clientObj = { ...this.clientObj, selectedStarterId };
        this.recomputeStepState();
    }

    handleNext = () => {
        const flow = {
            welcome: { step: 'name', oakLine: 'First, tell me. What is your name, Trainer?' },
            name: { step: 'rival', oakLine: 'Will you have a rival on this journey? Choose one, or go it alone.' },
            rival: { step: 'starter', oakLine: 'Now for the big decision. Which Pokemon will be your partner?' }
        };
        if(this.clientObj.step === 'name' && CheckBlank(this.clientObj.trainerName)){
            return ShowToast('Hold on', 'Please enter a trainer name.', 'warning');
        }
        const next = flow[this.clientObj.step];
        if(next){
            this.clientObj = { ...this.clientObj, step: next.step, oakLine: next.oakLine };
            this.recomputeStepState();
        }
    }

    handleBack = () => {
        const flow = {
            name: { step: 'welcome', oakLine: 'Hello there! Welcome to the world of Pokemon!' },
            rival: { step: 'name', oakLine: 'First, tell me. What is your name, Trainer?' },
            starter: { step: 'rival', oakLine: 'Will you have a rival on this journey? Choose one, or go it alone.' }
        };
        const previous = flow[this.clientObj.step];
        if(previous){
            this.clientObj = { ...this.clientObj, step: previous.step, oakLine: previous.oakLine };
            this.recomputeStepState();
        }
    }

    handleBeginAdventure = () => {
        if(this.clientObj.starterNotChosen) return ShowToast('Hold on', 'Please choose a starter Pokemon.', 'warning');
        this.clientObj = { ...this.clientObj, step: 'creating', oakLine: 'Setting up your Trainer Card and your very first Pokemon...' };
        this.recomputeStepState();
        this.loading = true;
        const params = {
            trainerName: this.clientObj.trainerName,
            rivalTrainerId: this.clientObj.rivalTrainerId || undefined,
            starterPokedexId: Number(this.clientObj.selectedStarterId)
        };
        CreateTrainer({ params }).then(result => {
            if(result.status === 'success'){
                this.finishOnboarding(result.trainer, 'success', 'Your adventure begins! Welcome, Trainer.');
            }
            else if(result.status === 'warning'){
                ShowToast('Welcome back', result.message, 'warning');
                this.finishOnboarding(result.trainer, null, null);
            }
            else{
                ShowToast('Error', result.message || 'Could not create your trainer.', 'error');
                this.clientObj = { ...this.clientObj, step: 'starter', oakLine: 'Now for the big decision. Which Pokemon will be your partner?' };
                this.recomputeStepState();
            }
            this.loading = false;
        }).catch(error => {
            this.loading = false;
            this.clientObj = { ...this.clientObj, step: 'starter', oakLine: 'Now for the big decision. Which Pokemon will be your partner?' };
            this.recomputeStepState();
            ShowError(error);
        });
    }

    finishOnboarding = (trainer, toastVariant, toastMessage) => {
        if(trainer && toastVariant){
            ShowToast('Success', toastMessage, toastVariant);
        }
        this.clientObj = { ...this.clientObj, step: 'done', oakLine: 'Off you go! The world of Pokemon awaits.' };
        this.recomputeStepState();
        if(trainer && trainer.Id){
            this.dispatchEvent(new CustomEvent('trainercreated', { detail: { trainerId: trainer.Id } }));
        }
    }

    handleImageError = (event) => {
        event.target.src = PLACEHOLDER_SPRITE;
    }

    handleClose = () => {
        this.dispatchEvent(new CustomEvent('close'));
    }
}