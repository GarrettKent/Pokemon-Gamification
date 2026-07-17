/* Title: pokemonBasics
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Shared LWC utilities for the Pokemon game — toast helpers, blank check, error-message extraction, and a results-map success guard. Package-owned (no LSC dependency).
 */
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const CheckBlank = (value) => value === '' || value === null || value === undefined || value === 'MALFORMED_ID';

const ShowToast = (title, message, variant) => dispatchEvent(new ShowToastEvent({ title, message, variant }));

// Pull a human-readable message out of an Apex/JS error — never a raw JSON blob in a toast.
const errorMessage = (error) =>
    (error && error.body && error.body.message) ||
    (error && error.message) ||
    'Something went wrong. Please try again.';

// Toast a thrown error with a clean message — safe to pass straight to .catch().
const ShowError = (error) => ShowToast('Error', errorMessage(error), 'error');

// True when a controller results map succeeded. On 'warning'/'error' it toasts the message and returns false,
// so callers guard with: if(!isSuccess(result)) return;
const isSuccess = (result) => {
    if(result && result.status === 'success') return true;
    const isWarning = result && result.status === 'warning';
    ShowToast(
        isWarning ? 'Heads up' : 'Error',
        (result && result.message) || 'The request could not be completed.',
        isWarning ? 'warning' : 'error'
    );
    return false;
};

export { CheckBlank, ShowToast, ShowError, errorMessage, isSuccess };
