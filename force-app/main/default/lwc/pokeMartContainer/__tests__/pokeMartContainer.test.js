/* Title: pokeMartContainer.test
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Smoke test for the pokeMartContainer LWC.
 */
import { createElement } from '@lwc/engine-dom';
import PokeMartContainer from 'c/pokeMartContainer';

jest.mock(
    '@salesforce/apex/pokemonGameController.GetMyTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: null })) }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/pokemonGameController.PurchaseItems',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: {} })) }),
    { virtual: true }
);

describe('c-poke-mart-container', () => {
    afterEach(() => {
        while(document.body.firstChild){
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders the Poke Mart card', () => {
        const element = createElement('c-poke-mart-container', { is: PokeMartContainer });
        document.body.appendChild(element);

        const card = element.shadowRoot.querySelector('.slds-card');
        expect(card).not.toBeNull();
    });
});
