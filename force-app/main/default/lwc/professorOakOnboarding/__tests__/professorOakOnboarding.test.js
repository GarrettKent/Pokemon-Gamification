import { createElement } from '@lwc/engine-dom';
import ProfessorOakOnboarding from 'c/professorOakOnboarding';

jest.mock(
    '@salesforce/apex/pokemonGameController.GetMyTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', currentUserName: 'Ash', trainer: null })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.GetOtherTrainers',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', otherTrainers: [] })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.CreateTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: { Id: 'a00' }, starter: {} })) }),
    { virtual: true }
);

describe('c-professor-oak-onboarding', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders Professor Oak header', () => {
        const element = createElement('c-professor-oak-onboarding', {
            is: ProfessorOakOnboarding
        });
        document.body.appendChild(element);

        const header = element.shadowRoot.querySelector('h1');
        expect(header.textContent).toBe("Professor Oak's Lab");
    });
});
