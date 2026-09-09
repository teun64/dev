// 2026-09-09 - TRi - refreshes Subscription25__Price__c from the pricebook for platforms where Salesforce
// (not the platform) owns pricing (see Util_PriceCalculation.PRICE_CALCULATED_PLATFORMS), right before a
// contract's native renewal. Runs at 00:05 Amsterdam time, ahead of Sub25's own Job_ContractManagement
// (01:16) - this is also the price refresh that Rest_UpsertContract's nightly no-op sync call used to
// perform before it started being short-circuited; this batch replaces that side effect.
global class Batch_UpdateContractProductPrice extends Subscription25.Job_AbstractBatch2 {

    private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

    global Batch_UpdateContractProductPrice() {
        super('Batch_UpdateContractProductPrice');
    }

    public override Integer getBatchSize() {
        return 25;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc){
        String platformList = '(\'' + String.join(new List<String>(Util_PriceCalculation.PRICE_CALCULATED_PLATFORMS), '\',\'') + '\')';
        Date renewingBy = Date.today().addDays(1);

        String query =
            'SELECT Id, Subscription25__Product__c, Subscription25__Quantity__c, Subscription25__Price__c, ' +
            'Subscription25__Contract__r.Pricebook2Id, Subscription25__Contract__r.CurrencyIsoCode, Subscription25__Contract__r.AccountId ' +
            'FROM Subscription25__Contract_Product__c ' +
            'WHERE Update_Price_before_Renewal__c = true ' +
            'AND Subscription25__Status__c IN (\'Ready\', \'Activated\') ' +
            'AND Subscription25__Contract__r.System_Platform__c IN ' + platformList + ' ' +
            'AND Subscription25__Contract__r.Subscription25__Current_End_Date__c <= ' + String.valueOf(renewingBy);

        return Database.getQueryLocator(query);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
        List<Subscription25__Contract_Product__c> toUpdate = new List<Subscription25__Contract_Product__c>();

        for (SObject so : scope) {
            Subscription25__Contract_Product__c cp = (Subscription25__Contract_Product__c) so;

            PricebookEntry pbe = Util_PriceCalculation.getPricebookEntry(
                cp.Subscription25__Product__c,
                cp.Subscription25__Contract__r.Pricebook2Id,
                cp.Subscription25__Contract__r.CurrencyIsoCode,
                cp.Subscription25__Contract__r.AccountId,
                Math.round(cp.Subscription25__Quantity__c),
                0.0
            );

            Decimal newPrice = ((pbe != null) ? pbe.SalesPrice__c : 0).setScale(2, RoundingMode.HALF_DOWN);

            if (newPrice != cp.Subscription25__Price__c) {
                toUpdate.add(new Subscription25__Contract_Product__c(Id = cp.Id, Subscription25__Price__c = newPrice));
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, RUNNING_MODE);
        }
    }

    public override void finishBatch(Database.BatchableContext bc){}
}
