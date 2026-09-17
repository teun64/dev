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
