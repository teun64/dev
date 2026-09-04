global class Batch_ActivateDraftContractProducts extends Subscription25.Job_AbstractBatch2 {

    private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

    global Batch_ActivateDraftContractProducts() {
        super('Batch_ActivateDraftContractProducts');
    }

    public override Integer getBatchSize() {
        return 1;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc){
        String query =
            'SELECT Id, Subscription25__Status__c, Subscription25__Contract__r.AccountId ' +
            'FROM Subscription25__Contract_Product__c ' +
            'WHERE Subscription25__Status__c = \'Draft\' LIMIT 20';
        return Database.getQueryLocator(query);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
        Subscription25__Contract_Product__c curContProd = (Subscription25__Contract_Product__c)scope[0];
        Id acctId = curContProd.Subscription25__Contract__r.AccountId;
        Account acct = [SELECT Id, Name, FinancialDebtorNumber__c FROM Account WHERE Id = :acctId WITH SYSTEM_MODE];

        if (String.isNotBlank(acct.FinancialDebtorNumber__c)) {
            curContProd.Subscription25__Status__c = 'Activated';
            database.update(curContProd, RUNNING_MODE);
        } else {
            //account has no debtor number yet for its administration; mark it and stop here for now instead of auto-syncing
            Event_Log__c markLog = Util_Event.getLog(null, 'S', 'S', 'Account', 'ActivateDraftContractProduct', acctId, acct.Name, curContProd.Id);
            markLog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
            markLog.Integration_Status__c = Util_Event.LogEventStatus.CANCELLED.name();
            markLog.Message__c = 'Account ' + acctId + ' has no FinancialDebtorNumber__c; skipping activation of Contract Product ' + curContProd.Id + ' for now.';
            database.insert(markLog, RUNNING_MODE);
        }
    }

    public override void finishBatch(Database.BatchableContext bc){}
}