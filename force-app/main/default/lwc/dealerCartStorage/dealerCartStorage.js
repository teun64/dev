const STORAGE_KEY = 'dealerShopCart';

// Internal quick-action usage passes accountId so each dealer Account gets its own cart, scoped
// separately in the SAME browser session - without this, adding a product while viewing Account A
// then opening the shop for Account B (same tab) would carry A's cart straight into B's order.
// Portal usage never passes accountId (a portal session only ever has one dealer account), so it
// keeps the original unscoped key.
function storageKey(accountId) {
    return accountId ? `${STORAGE_KEY}_${accountId}` : STORAGE_KEY;
}

function readRaw(accountId) {
    try {
        const raw = window.sessionStorage.getItem(storageKey(accountId));
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

function writeRaw(items, accountId) {
    try {
        window.sessionStorage.setItem(storageKey(accountId), JSON.stringify(items));
    } catch (e) {
        // sessionStorage unavailable (private browsing, etc.) - cart just won't persist
    }
}

export function getCart(accountId) {
    return readRaw(accountId);
}

export function saveCart(items, accountId) {
    writeRaw(items || [], accountId);
}

export function clearCart(accountId) {
    writeRaw([], accountId);
}

// Merges { productId, quantity, unitPrice } items into the stored cart, summing quantities for
// products already present (matching dealerShop's own add-to-cart behavior).
export function mergeItemsIntoCart(newItems, accountId) {
    const cart = readRaw(accountId);
    (newItems || []).forEach((incoming) => {
        const existing = cart.find((i) => i.productId === incoming.productId);
        if (existing) {
            existing.quantity = (existing.quantity || 1) + (incoming.quantity || 1);
            existing.unitPrice = incoming.unitPrice;
        } else {
            cart.push({ ...incoming });
        }
    });
    writeRaw(cart, accountId);
    return cart;
}

// Order options (customer reference + delivery address choice) live next to the cart, under the
// same account scoping, so they survive navigating between shop pages - and a reorder from order
// history can hand over the original order's delivery address.
const OPTIONS_KEY = 'dealerShopOrderOptions';

function optionsKey(accountId) {
    return accountId ? `${OPTIONS_KEY}_${accountId}` : OPTIONS_KEY;
}

export function getOrderOptions(accountId) {
    try {
        const raw = window.sessionStorage.getItem(optionsKey(accountId));
        return raw ? JSON.parse(raw) : null;
    } catch (e) {
        return null;
    }
}

export function saveOrderOptions(options, accountId) {
    try {
        window.sessionStorage.setItem(optionsKey(accountId), JSON.stringify(options || {}));
    } catch (e) {
        // sessionStorage unavailable - options just won't persist
    }
}

export function clearOrderOptions(accountId) {
    try {
        window.sessionStorage.removeItem(optionsKey(accountId));
    } catch (e) {
        // ignore
    }
}
