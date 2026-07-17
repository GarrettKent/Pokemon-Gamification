import { createElement } from '@lwc/engine-dom';
import TrainerDashboard from 'c/trainerDashboard';

jest.mock(
    '@salesforce/apex/pokemonGameController.GetMyTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: null, pokemon: [] })) }),
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/pokemonGameController.GetTrainer',
    () => ({ default: jest.fn(() => Promise.resolve({ status: 'success', trainer: null, pokemon: [] })) }),
    { virtual: true }
);

describe('c-trainer-dashboard', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('renders without throwing', () => {
        const element = createElement('c-trainer-dashboard', {
            is: TrainerDashboard
        });

        document.body.appendChild(element);

        expect(element).not.toBeNull();
    });

    it('buildBadges does not throw when trainer is null', () => {
        const element = createElement('c-trainer-dashboard', {
            is: TrainerDashboard
        });

        expect(() => element.buildBadges(null)).not.toThrow();
    });
});
