import { createElement } from '@lwc/engine-dom';
import BiomeExplorer from 'c/biomeExplorer';
import GetMyTrainer from '@salesforce/apex/pokemonGameController.GetMyTrainer';
import GetBiomePokemon from '@salesforce/apex/pokemonGameController.GetBiomePokemon';

jest.mock(
    '@salesforce/apex/pokemonGameController.GetMyTrainer',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.GetBiomePokemon',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.RevealEncounter',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', dex: 25, name: 'pikachu', image: 'x', type1: 'electric', level: 5, isShiny: false })) }),
    { virtual: true }
);

const ALL_BIOMES = ['Azure_Shore', 'Mystic_Mirage', 'Rocky_Cavern', 'Scorched_Summit', 'Spectral_Graveyard', 'Verdant_Meadow'];

const flushPromises = () => new Promise(resolve => setTimeout(resolve, 0));

const buildExplorer = () => {
    const element = createElement('c-biome-explorer', { is: BiomeExplorer });
    document.body.appendChild(element);
    return element;
};

const clickBiome = (element, biome) => {
    const tiles = [...element.shadowRoot.querySelectorAll('button[data-biome]')];
    tiles.find(tile => tile.dataset.biome === biome).click();
    return flushPromises();
};

describe('c-biome-explorer', () => {
    beforeEach(() => {
        jest.clearAllMocks();
        GetMyTrainer.mockResolvedValue({ status: 'success', trainer: null, pokemon: [] });
        GetBiomePokemon.mockResolvedValue({ status: 'success', patches: [], backgroundImageUrl: '' });
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the explore card', () => {
        const element = buildExplorer();

        const card = element.shadowRoot.querySelector('article.explorer-panel');
        expect(card).not.toBeNull();
    });

    it('does not pre-roll biomes without a trainer', async () => {
        buildExplorer();
        await flushPromises();

        expect(GetBiomePokemon).not.toHaveBeenCalled();
    });

    it('pre-rolls all six biomes once at load when a trainer exists', async () => {
        GetMyTrainer.mockResolvedValue({ status: 'success', trainer: { Id: 'a01000000000001AAA', Poke_Balls__c: 10 }, pokemon: [] });

        buildExplorer();
        await flushPromises();

        expect(GetBiomePokemon).toHaveBeenCalledTimes(6);
        const requestedBiomes = GetBiomePokemon.mock.calls.map(call => call[0].params.biome).sort();
        expect(requestedBiomes).toEqual(ALL_BIOMES);
    });

    it('switching between biomes reuses the pre-rolled patches and never re-rolls', async () => {
        GetMyTrainer.mockResolvedValue({ status: 'success', trainer: { Id: 'a01000000000001AAA', Poke_Balls__c: 10 }, pokemon: [] });
        GetBiomePokemon.mockImplementation(({ params }) =>
            Promise.resolve({ status: 'success', patches: [{ token: `token-${params.biome}`, isShiny: false }], backgroundImageUrl: '' })
        );

        const element = buildExplorer();
        await flushPromises();

        await clickBiome(element, 'Verdant_Meadow');
        await clickBiome(element, 'Rocky_Cavern');
        await clickBiome(element, 'Verdant_Meadow');

        expect(GetBiomePokemon).toHaveBeenCalledTimes(6);
        const patches = element.shadowRoot.querySelectorAll('button.grass-patch');
        expect(patches.length).toBe(1);
    });
});
