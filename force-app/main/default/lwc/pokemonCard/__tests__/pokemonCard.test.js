import { createElement } from '@lwc/engine-dom';
import PokemonCard from 'c/pokemonCard';

jest.mock(
    '@salesforce/apex/pokemonGameController.RenamePokemon',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.PowerUpPokemon',
    () => ({ default: jest.fn() }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.ReleasePokemon',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

describe('c-pokemon-card', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders the card for a provided pokemon', () => {
        // Arrange
        const element = createElement('c-pokemon-card', { is: PokemonCard });
        element.pokemon = {
            Id: 'a00000000000001',
            Species_Name__c: 'Pikachu',
            Nickname__c: '',
            Pokedex_Number__c: 25,
            Level__c: 5,
            Image__c: 'https://example.com/25.png',
            Type__c: 'electric',
            HP__c: 35,
            Attack__c: 55,
            Defense__c: 40,
            Special_Attack__c: 50,
            Special_Defense__c: 50,
            Speed__c: 90,
            Is_Shiny__c: false,
            Is_Traded__c: false
        };
        element.availableTokens = 10;

        // Act
        document.body.appendChild(element);

        // Assert
        const card = element.shadowRoot.querySelector('.poke-card');
        expect(card).not.toBeNull();
    });
});
