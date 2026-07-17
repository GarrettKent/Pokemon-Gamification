import { createElement } from '@lwc/engine-dom';
import WildEncounterModal from 'c/wildEncounterModal';

jest.mock(
    '@salesforce/apex/pokemonGameController.CatchPokemon',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', caught: true })) }),
    { virtual: true }
);

describe('c-wild-encounter-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the wild Pokemon name and dex', () => {
        const element = createElement('c-wild-encounter-modal', { is: WildEncounterModal });
        element.encounter = { token: 'test-token', dex: 25, name: 'Pikachu', image: 'x', type1: 'electric', level: 5, isShiny: false };
        element.ballCounts = { pokeball: 5, greatball: 0, ultraball: 0, masterball: 0 };
        document.body.appendChild(element);

        const heading = element.shadowRoot.querySelector('h1');
        expect(heading.textContent).toContain('wild Pokemon');
    });
});
