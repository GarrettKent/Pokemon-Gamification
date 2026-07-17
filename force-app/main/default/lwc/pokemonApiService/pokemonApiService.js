/* Title: pokemonApiService
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: Read-only client helpers for the Pokemon game — PokeAPI browse/preview fetch, the packaged species seed (for legendary/mythical lookup), the canonical 18-type color palette, and display formatters. No writes, no economy logic (that is server-authoritative in pokemonGameController).
 * Modified: Garrett Kent - 06/22/2026 - Added stoneIconUrl + 5 evolution-stone icon imports
 * Modified: Garrett Kent - 06/22/2026 - Added Shiny/Dusk/Dawn evolution stones
 */
import POKEMON_SEED from '@salesforce/resourceUrl/pokemonSpeciesSeed';
import POKE_BALL_ICON from '@salesforce/resourceUrl/pokeBallIcon';
import GREAT_BALL_ICON from '@salesforce/resourceUrl/greatBallIcon';
import ULTRA_BALL_ICON from '@salesforce/resourceUrl/ultraBallIcon';
import MASTER_BALL_ICON from '@salesforce/resourceUrl/masterBallIcon';
import FIRE_STONE_ICON from '@salesforce/resourceUrl/fireStoneIcon';
import WATER_STONE_ICON from '@salesforce/resourceUrl/waterStoneIcon';
import THUNDER_STONE_ICON from '@salesforce/resourceUrl/thunderStoneIcon';
import LEAF_STONE_ICON from '@salesforce/resourceUrl/leafStoneIcon';
import MOON_STONE_ICON from '@salesforce/resourceUrl/moonStoneIcon';
import SHINY_STONE_ICON from '@salesforce/resourceUrl/shinyStoneIcon';
import DUSK_STONE_ICON from '@salesforce/resourceUrl/duskStoneIcon';
import DAWN_STONE_ICON from '@salesforce/resourceUrl/dawnStoneIcon';

const POKEAPI_BASE = 'https://pokeapi.co/api/v2';
const ARTWORK_BASE = 'https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork';

// Canonical 18-type palette — the one justified color-by-data case (drives an inline style on type chips).
const TYPE_COLORS = {
    normal: '#A8A77A', fire: '#EE8130', water: '#6390F0', electric: '#F7D02C',
    grass: '#7AC74C', ice: '#96D9D6', fighting: '#C22E28', poison: '#A33EA1',
    ground: '#E2BF65', flying: '#A98FF3', psychic: '#F95587', bug: '#A6B91A',
    rock: '#B6A136', ghost: '#735797', dragon: '#6F35FC', dark: '#705746',
    steel: '#B7B7CE', fairy: '#D685AD'
};

// Neutral Poke Ball silhouette — renders even when the sprite host is blocked or the image 404s.
const PLACEHOLDER_SPRITE = `data:image/svg+xml,${encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="46" fill="#f3f3f3" stroke="#c9c9c9" stroke-width="3"/><path d="M4 50h28a18 18 0 0 1 36 0h28" fill="none" stroke="#c9c9c9" stroke-width="6"/><circle cx="50" cy="50" r="12" fill="#fff" stroke="#c9c9c9" stroke-width="5"/></svg>`
)}`;

let seedPromise = null;

const loadSeed = () => {
    if(seedPromise) return seedPromise;
    seedPromise = fetch(POKEMON_SEED)
        .then(response => response.json())
        .catch(() => ({}));
    return seedPromise;
};

const getSeedSpecies = (pokedexNumber) => loadSeed().then(seed => seed[String(pokedexNumber)] || null);

const buildArtworkUrl = (pokedexNumber, isShiny) =>
    isShiny ? `${ARTWORK_BASE}/shiny/${pokedexNumber}.png` : `${ARTWORK_BASE}/${pokedexNumber}.png`;

const typeColor = (typeName) => TYPE_COLORS[(typeName || '').toLowerCase()] || '#68A090';

// Pick black or white text for legibility against the chip's type color (relative luminance).
const readableTextColor = (hexColor) => {
    const red = parseInt(hexColor.slice(1, 3), 16);
    const green = parseInt(hexColor.slice(3, 5), 16);
    const blue = parseInt(hexColor.slice(5, 7), 16);
    const luminance = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;
    return luminance > 0.6 ? '#202020' : '#ffffff';
};

const typeChipStyle = (typeName) => {
    const background = typeColor(typeName);
    return `background-color: ${background}; color: ${readableTextColor(background)};`;
};

const formatDex = (pokedexNumber) => `#${String(pokedexNumber || 0).padStart(3, '0')}`;

const capitalize = (text) => (text ? `${text.charAt(0).toUpperCase()}${text.slice(1)}` : '');

// Accepts any ball key form — 'poke', 'pokeball', 'Poke Ball', 'master_balls' — and returns its sprite URL.
const ballIconUrl = (ballKey) => {
    const normalized = (ballKey || '').toLowerCase().replace(/[^a-z]/g, '');
    if(normalized.indexOf('great') === 0) return GREAT_BALL_ICON;
    if(normalized.indexOf('ultra') === 0) return ULTRA_BALL_ICON;
    if(normalized.indexOf('master') === 0) return MASTER_BALL_ICON;
    return POKE_BALL_ICON;
};

// Accepts any stone key form — 'fire', 'Fire Stone', 'thunder_stones' — and returns its sprite URL.
const stoneIconUrl = (stoneKey) => {
    const normalized = (stoneKey || '').toLowerCase().replace(/[^a-z]/g, '');
    if(normalized.indexOf('water') === 0) return WATER_STONE_ICON;
    if(normalized.indexOf('thunder') === 0) return THUNDER_STONE_ICON;
    if(normalized.indexOf('leaf') === 0) return LEAF_STONE_ICON;
    if(normalized.indexOf('moon') === 0) return MOON_STONE_ICON;
    if(normalized.indexOf('shiny') === 0) return SHINY_STONE_ICON;
    if(normalized.indexOf('dusk') === 0) return DUSK_STONE_ICON;
    if(normalized.indexOf('dawn') === 0) return DAWN_STONE_ICON;
    return FIRE_STONE_ICON;
};

export {
    getSeedSpecies,
    buildArtworkUrl,
    typeChipStyle,
    formatDex,
    capitalize,
    PLACEHOLDER_SPRITE,
    ballIconUrl,
    stoneIconUrl
};