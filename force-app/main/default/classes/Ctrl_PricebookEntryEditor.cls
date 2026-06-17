public without sharing class Ctrl_PricebookEntryEditor {
    public static Boolean eventPublished;

    @AuraEnabled
    public static void updateListPrice(
        Id pricebookEntryId,
        Decimal newPrice
    ) {
        eventPublished = false;

        validatePrice(newPrice);
 
        PricebookEntry pbe = [
            SELECT Id, UnitPrice, CurrencyIsoCode
            FROM PricebookEntry
            WHERE Id = :pricebookEntryId
            LIMIT 1
            FOR UPDATE
        ];

        Decimal oldPrice = pbe.UnitPrice;

        if (newPrice == oldPrice) {
            return; // no-op update
        }
        
        pbe.UnitPrice = newPrice;
        update pbe;

        // Publish platform event
        Internal__e evt =
            new Internal__e(
                Record__c = pbe.Id,
                Object__c = 'PricebookEntry',
                Action__c = 'PriceAgreements',
                ChangedBy__c = UserInfo.getUserId()
            );

        Database.SaveResult sr = EventBus.publish(evt);
        eventPublished = sr.isSuccess();

        if (!eventPublished) {
            rollbackPrice(pbe, oldPrice);
        }
    }

    // --------------------------------------------------------------------------------------------
    // Helper methods
    // --------------------------------------------------------------------------------------------
    private static void validatePrice(Decimal newPrice) {
        if ((newPrice == null) || (newPrice < 0)) {
            throwAuraException('Price must be 0 or higher');
        }
    }

    private static void rollbackPrice(PricebookEntry pbe, Decimal oldPrice) {
        pbe.UnitPrice = oldPrice;
        update pbe;

        throwAuraException('Platform Event publish failed, price update rolled back');
    }

    private static void throwAuraException(String message) {
        throw new AuraHandledException(message);
    }
}
