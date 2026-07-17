/* Title: pokeMartContainer
 * Created By: Garrett Kent - 06/20/2026
 * Purpose: The Poke Mart shop — spend Currency on Poke Balls and Evolution Stones with a server-authoritative debit.
 * Modified: Garrett Kent - 06/21/2026 - Added Evolution Stones shelf, pockets, and cart math.
 * Modified: Garrett Kent - 06/22/2026 - Real stone sprites; two-column layout (items left, summary panel right).
 * Modified: Garrett Kent - 06/22/2026 - Added Shiny/Dusk/Dawn evolution stones
 * Modified: Garrett Kent - 06/25/2026 - Repriced balls (200/400/600) and stones (5000); prices mirror Pokemon_Settings__mdt
 * Modified: Garrett Kent - 07/05/2026 - Compact shelves: dense line-item rows with a +/- quantity stepper replace the per-item cards
 */
import { LightningElement, track } from 'lwc';
import { ShowToast, ShowError, isSuccess } from 'c/pokemonBasics';
import { ballIconUrl, stoneIconUrl } from 'c/pokemonApiService';
import GetMyTrainer from '@salesforce/apex/pokemonGameController.GetMyTrainer';
import PurchaseItems from '@salesforce/apex/pokemonGameController.PurchaseItems';

const PRICES = { pokeball: 200, greatball: 400, ultraball: 600 };
const STONE_PRICE = 5000;

export default class PokeMartContainer extends LightningElement {
    @track clientObj = {
        trainer: {},
        cart: {
            pokeball: 0,
            greatball: 0,
            ultraball: 0,
            firestone: 0,
            waterstone: 0,
            thunderstone: 0,
            leafstone: 0,
            moonstone: 0,
            shinystone: 0,
            duskstone: 0,
            dawnstone: 0
        },
        hasTrainer: false,
        showEmptyState: false,
        currencyBalance: 0,
        ballBalances: [],
        stoneBalances: [],
        ownedItems: [],
        catalogItems: [],
        stoneItems: [],
        cartTotal: 0,
        remainingBalance: 0,
        canAfford: false,
        buyDisabled: true
    };

    loading = false;
    debug = false;

    catalog = [
        { key: 'pokeball', name: 'Poke Ball', price: PRICES.pokeball },
        { key: 'greatball', name: 'Great Ball', price: PRICES.greatball },
        { key: 'ultraball', name: 'Ultra Ball', price: PRICES.ultraball }
    ];

    stoneCatalog = [
        { key: 'firestone', name: 'Fire Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('firestone') },
        { key: 'waterstone', name: 'Water Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('waterstone') },
        { key: 'thunderstone', name: 'Thunder Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('thunderstone') },
        { key: 'leafstone', name: 'Leaf Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('leafstone') },
        { key: 'moonstone', name: 'Moon Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('moonstone') },
        { key: 'shinystone', name: 'Shiny Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('shinystone') },
        { key: 'duskstone', name: 'Dusk Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('duskstone') },
        { key: 'dawnstone', name: 'Dawn Stone', price: STONE_PRICE, iconUrl: stoneIconUrl('dawnstone') }
    ];

    connectedCallback() {
        this.recomputeTrainerState();
        this.recomputeCart();
        this.loadTrainer();
    }

    loadTrainer = () => {
        this.loading = true;
        this.recomputeTrainerState();
        GetMyTrainer({ params: { includePokemon: false } })
            .then((result) => {
                if(!isSuccess(result)) return;
                this.clientObj = { ...this.clientObj, trainer: result.trainer || {} };
                this.recomputeTrainerState();
                this.recomputeCart();
            })
            .catch(ShowError)
            .finally(() => {
                this.loading = false;
                this.recomputeTrainerState();
                this.recomputeCart();
            });
    };

    handleQuantityChange = (event) => {
        const ballKey = event.currentTarget.dataset.ball;
        const quantity = parseInt(event.target.value, 10);
        const safeQuantity = isNaN(quantity) || quantity < 0 ? 0 : quantity;
        this.clientObj = {
            ...this.clientObj,
            cart: { ...this.clientObj.cart, [ballKey]: safeQuantity }
        };
        this.recomputeCart();
    };

    adjustQuantity = (event) => {
        const itemKey = event.currentTarget.dataset.item;
        const delta = parseInt(event.currentTarget.dataset.delta, 10);
        const nextQuantity = Math.max(0, (this.clientObj.cart[itemKey] || 0) + delta);
        this.clientObj = {
            ...this.clientObj,
            cart: { ...this.clientObj.cart, [itemKey]: nextQuantity }
        };
        this.recomputeCart();
    };

    handleBuy = () => {
        if(!this.clientObj.canAfford) return;
        this.loading = true;
        this.recomputeCart();
        PurchaseItems({ params: { cart: this.clientObj.cart } })
            .then((result) => {
                if(!isSuccess(result)) return;
                this.clientObj = {
                    ...this.clientObj,
                    trainer: result.trainer,
                    cart: {
                        pokeball: 0,
                        greatball: 0,
                        ultraball: 0,
                        firestone: 0,
                        waterstone: 0,
                        thunderstone: 0,
                        leafstone: 0,
                        moonstone: 0,
                        shinystone: 0,
                        duskstone: 0,
                        dawnstone: 0
                    }
                };
                this.recomputeTrainerState();
                this.recomputeCart();
                ShowToast('Thanks!', 'Your items are ready for adventure.', 'success');
                this.dispatchEvent(new CustomEvent('balancechanged', { detail: { trainer: result.trainer } }));
            })
            .catch(ShowError)
            .finally(() => {
                this.loading = false;
                this.recomputeTrainerState();
                this.recomputeCart();
            });
    };

    recomputeTrainerState = () => {
        const trainer = this.clientObj.trainer || {};
        const hasTrainer = !!(trainer && trainer.Id);
        const currencyBalance = hasTrainer ? trainer.Currency__c || 0 : 0;
        const ballBalances = [
            { key: 'pokeball', name: 'Poke Balls', sprite: ballIconUrl('poke'), count: trainer.Poke_Balls__c || 0 },
            { key: 'greatball', name: 'Great Balls', sprite: ballIconUrl('great'), count: trainer.Great_Balls__c || 0 },
            { key: 'ultraball', name: 'Ultra Balls', sprite: ballIconUrl('ultra'), count: trainer.Ultra_Balls__c || 0 },
            { key: 'masterball', name: 'Master Balls', sprite: ballIconUrl('master'), count: trainer.Master_Balls__c || 0 }
        ];
        const stoneBalances = [
            { key: 'firestone', name: 'Fire Stones', iconUrl: stoneIconUrl('firestone'), count: trainer.Fire_Stones__c || 0 },
            { key: 'waterstone', name: 'Water Stones', iconUrl: stoneIconUrl('waterstone'), count: trainer.Water_Stones__c || 0 },
            { key: 'thunderstone', name: 'Thunder Stones', iconUrl: stoneIconUrl('thunderstone'), count: trainer.Thunder_Stones__c || 0 },
            { key: 'leafstone', name: 'Leaf Stones', iconUrl: stoneIconUrl('leafstone'), count: trainer.Leaf_Stones__c || 0 },
            { key: 'moonstone', name: 'Moon Stones', iconUrl: stoneIconUrl('moonstone'), count: trainer.Moon_Stones__c || 0 },
            { key: 'shinystone', name: 'Shiny Stones', iconUrl: stoneIconUrl('shinystone'), count: trainer.Shiny_Stones__c || 0 },
            { key: 'duskstone', name: 'Dusk Stones', iconUrl: stoneIconUrl('duskstone'), count: trainer.Dusk_Stones__c || 0 },
            { key: 'dawnstone', name: 'Dawn Stones', iconUrl: stoneIconUrl('dawnstone'), count: trainer.Dawn_Stones__c || 0 }
        ];
        const ownedItems = [...ballBalances, ...stoneBalances].map((item) => ({
            key: item.key,
            name: item.name,
            icon: item.sprite || item.iconUrl,
            count: item.count
        }));
        this.clientObj = {
            ...this.clientObj,
            hasTrainer,
            currencyBalance,
            ballBalances,
            stoneBalances,
            ownedItems,
            showEmptyState: !this.loading && !hasTrainer
        };
    };

    recomputeCart = () => {
        const cart = this.clientObj.cart;
        const currencyBalance = this.clientObj.currencyBalance;
        const catalogItems = this.catalog.map((item) => ({
            ...item,
            sprite: ballIconUrl(item.key),
            quantity: cart[item.key] || 0,
            lineTotal: (cart[item.key] || 0) * item.price
        }));
        const stoneItems = this.stoneCatalog.map((item) => ({
            ...item,
            quantity: cart[item.key] || 0,
            lineTotal: (cart[item.key] || 0) * item.price
        }));
        const ballTotal = cart.pokeball * PRICES.pokeball + cart.greatball * PRICES.greatball + cart.ultraball * PRICES.ultraball;
        const stoneTotal = (cart.firestone + cart.waterstone + cart.thunderstone + cart.leafstone + cart.moonstone + cart.shinystone + cart.duskstone + cart.dawnstone) * STONE_PRICE;
        const cartTotal = ballTotal + stoneTotal;
        const canAfford = cartTotal > 0 && cartTotal <= currencyBalance;
        this.clientObj = {
            ...this.clientObj,
            catalogItems,
            stoneItems,
            cartTotal,
            remainingBalance: currencyBalance - cartTotal,
            canAfford,
            buyDisabled: !canAfford || this.loading
        };
    };
}
