// Domain TLD determines the visitor's language - dealer.movingintelligence.nl -> nl_NL,
// .de -> de, .fr -> fr, everything else (.com, .co.uk, the my.site.com sandbox domain,
// localhost during dev) falls back to en. Values must match this org's actual registered
// translation locale codes (see force-app/main/default/translations/*.translation-meta.xml
// file names) - Dutch is registered as nl_NL, not nl. Shared by dealerHome and dealerShop
// so both resolve the same visitor language the same way.
const HOSTNAME_LANGUAGE_MAP = { '.nl': 'nl_NL', '.de': 'de', '.fr': 'fr' };

export function resolveLanguageFromHostname() {
    const host = window.location.hostname;
    for (const [suffix, lang] of Object.entries(HOSTNAME_LANGUAGE_MAP)) {
        if (host.endsWith(suffix)) return lang;
    }
    return 'en';
}

// Number-formatting locale for Intl.NumberFormat/toLocaleString, keyed by the same language
// values resolveLanguageFromHostname() returns. Only affects digit grouping/decimal separators
// (1.234,56 vs 1,234.56) - NOT the currency symbol, which still needs the account's real
// CurrencyIsoCode (not reliably derivable from language alone, since 'en' is also the generic
// fallback for domains that aren't actually UK/GBP).
const LANGUAGE_TO_LOCALE = { nl_NL: 'nl-NL', de: 'de-DE', fr: 'fr-FR', en: 'en-GB' };

export function resolveNumberLocale(language) {
    return LANGUAGE_TO_LOCALE[language] || 'en-GB';
}

// English defaults for the menu and order pages - shown until Ctrl_DealerPortal.getPortalLabels()
// resolves, and the list of labels it must return (same pattern as DEFAULT_LABELS in dealerShop).
export const ORDER_DEFAULT_LABELS = {
    DealerNav_Home: 'Home',
    DealerNav_Shop: 'Shop',
    DealerNav_OrderHistory: 'Order History',
    DealerNav_Logout: 'Log out',
    DealerNav_Login: 'Log in',
    DealerOrder_HistoryTitle: 'Order history',
    DealerOrder_MyOrders: 'My orders',
    DealerOrder_AllOrders: 'All orders',
    DealerOrder_Loading: 'Loading...',
    DealerOrder_NoOrders: 'No orders found',
    DealerOrder_OrderNumber: 'Order number',
    DealerOrder_Date: 'Date',
    DealerOrder_Status: 'Status',
    DealerOrder_PlacedBy: 'Ordered by',
    DealerOrder_Total: 'Total',
    DealerOrder_Reorder: 'Order again',
    DealerOrder_BackToHistory: 'Back to order history',
    DealerOrder_NoOrderGiven: 'No order specified.',
    DealerOrder_LoadError: 'An error occurred while loading the order.',
    DealerOrder_ReorderAll: 'Order the whole order again',
    DealerOrder_NoProducts: 'No products found for this order',
    DealerOrder_Product: 'Product',
    DealerOrder_Quantity: 'Quantity',
    DealerOrder_PriceThen: 'Price at the time',
    DealerOrder_PriceNow: 'Current price',
    DealerOrder_Add: 'Add',
    DealerOrder_Status_Webshop: 'Received',
    DealerOrder_Status_Administration: 'In progress',
    DealerOrder_Status_ClosedWon: 'Processed',
    DealerOrder_Status_ClosedLost: 'Cancelled'
};

// Opportunity StageName -> dealer-facing status (DealerOrder_Status_<stage without spaces>);
// a stage without a label is shown as is.
export function orderStatusLabel(labels, stageName) {
    if (!stageName) return '';
    return labels[`DealerOrder_Status_${stageName.replace(/\s+/g, '')}`] || stageName;
}
