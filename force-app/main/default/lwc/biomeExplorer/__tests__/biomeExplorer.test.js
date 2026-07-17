import { createElement } from '@lwc/engine-dom';
import BiomeExplorer from 'c/biomeExplorer';

jest.mock(
    '@salesforce/apex/pokemonGameController.GetMyTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: null, pokemon: [] })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.GetBiomePokemon',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', patches: [], backgroundImageUrl: '' })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.RevealEncounter',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', dex: 25, name: 'pikachu', image: 'x', type1: 'electric', level: 5, isShiny: false })) }),
    { virtual: true }
);

describe('c-biome-explorer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the explore card', () => {
        const element = createElement('c-biome-explorer', { is: BiomeExplorer });
        document.body.appendChild(element);

        const card = element.shadowRoot.querySelector('article.explorer-panel');
        expect(card).not.toBeNull();
    });
});
