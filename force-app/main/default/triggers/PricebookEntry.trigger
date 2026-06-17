trigger PriceBookEntryTrigger on PriceBookEntry (after update) {

    List<OpportunityLineItem> itemsToUpdate = new List<OpportunityLineItem>();

    for (PriceBookEntry pbe : Trigger.new) {
        PriceBookEntry oldPbe = Trigger.oldMap.get(pbe.Id);

        if (oldPbe.UnitPrice != pbe.UnitPrice) {
            // Query related Opportunity Line Items
            for (OpportunityLineItem oli : [
                SELECT Id, UnitPrice
                FROM OpportunityLineItem
                WHERE PriceBookEntryId = :pbe.Id
            ]) {
                oli.UnitPrice = pbe.UnitPrice; // or custom logic
                itemsToUpdate.add(oli);
            }
        }
    }

    if (!itemsToUpdate.isEmpty()) {
        update itemsToUpdate;
    }
}