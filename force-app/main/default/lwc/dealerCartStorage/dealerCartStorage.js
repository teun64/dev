const STORAGE_KEY = 'dealerShopCart';

function readRaw() {
    try {
        const raw = window.sessionStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

function writeRaw(items) {
    try {
        window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(items));
    } catch (e) {
        // sessionStorage unavailable (private browsing, etc.) - cart just won't persist
    }
}

export function getCart() {
    return readRaw();
}

export function saveCart(items) {
    writeRaw(items || []);
}

export function clearCart() {
    writeRaw([]);
}

// Merges { productId, quantity, unitPrice } items into the stored cart, summing quantities for
// products already present (matching dealerShop's own add-to-cart behavior).
export function mergeItemsIntoCart(newItems) {
    const cart = readRaw();
    (newItems || []).forEach((incoming) => {
        const existing = cart.find((i) => i.productId === incoming.productId);
        if (existing) {
            existing.quantity = (existing.quantity || 1) + (incoming.quantity || 1);
            existing.unitPrice = incoming.unitPrice;
        } else {
            cart.push({ ...incoming });
        }
    });
    writeRaw(cart);
    return cart;
}
