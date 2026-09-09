global class Batch_ActivateDraftContractProducts extends Subscription25.Job_AbstractBatch2 {

    private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

    global Batch_ActivateDraftContractProducts() {
        super('Batch_ActivateDraftContractProducts');
    }

    public override Integer getBatchSize() {
        return 100;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc){
        //no LIMIT here on purpose - a QueryLocator already iterates the full matching result set across
        //chunks; capping it artificially caps how many Draft records this job can ever clear per run,
        //which can build an unrecoverable backlog if Draft records ever accumulate faster than that cap
        String query =
            'SELECT Id, Subscription25__Status__c, Subscription25__Contract__r.AccountId ' +
            'FROM Subscription25__Contract_Product__c ' +
            'WHERE Subscription25__Status__c = \'Draft\'';
        return Database.getQueryLocator(query);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
        List<Subscription25__Contract_Product__c> contractProducts = (List<Subscription25__Contract_Product__c>) scope;

        Set<Id> acctIds = new Set<Id>();
        for (Subscription25__Contract_Product__c cp : contractProducts) {
            acctIds.add(cp.Subscription25__Contract__r.AccountId);
        }

        Map<Id, Account> acctsById = new Map<Id, Account>(
            [SELECT Id, Name, FinancialDebtorNumber__c FROM Account WHERE Id IN :acctIds WITH SYSTEM_MODE]
        );

        List<Subscription25__Contract_Product__c> toActivate = new List<Subscription25__Contract_Product__c>();
        List<Event_Log__c> toLog = new List<Event_Log__c>();

        for (Subscription25__Contract_Product__c cp : contractProducts) {
            Id acctId = cp.Subscription25__Contract__r.AccountId;
            Account acct = acctsById.get(acctId);

            if ((acct != null) && (String.isNotBlank(acct.FinancialDebtorNumber__c))) {
                toActivate.add(new Subscription25__Contract_Product__c(Id = cp.Id, Subscription25__Status__c = 'Activated'));
            } else {
                //account has no debtor number yet for its administration; mark it and stop here for now instead of auto-syncing
                Event_Log__c markLog = Util_Event.getLog(null, 'S', 'S', 'Account', 'ActivateDraftContractProduct', acctId, acct?.Name, cp.Id);
                markLog.Result_Status__c = Util_Event.LogResultStatus.WARNING.name();
                markLog.Integration_Status__c = Util_Event.LogEventStatus.CANCELLED.name();
                markLog.Message__c = 'Account ' + acctId + ' has no FinancialDebtorNumber__c; skipping activation of Contract Product ' + cp.Id + ' for now.';
                toLog.add(markLog);
            }
        }

        if (!toActivate.isEmpty()) {
            //partial success (not all-or-none) - a chunk can hold up to 100 unrelated records, and one
            //record failing its own validation must not roll back every other legitimate activation in
            //the same chunk along with it
            List<Database.SaveResult> saveResults = Database.update(toActivate, false, RUNNING_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (!saveResults[i].isSuccess()) {
                    toLog.add(buildFailureLog(toActivate[i].Id, saveResults[i].getErrors()));
                }
            }
        }
        if (!toLog.isEmpty()) {
            Database.insert(toLog, false, RUNNING_MODE);
        }
    }

    private Event_Log__c buildFailureLog(Id contractProductId, List<Database.Error> errors){
        List<String> errorMessages = new List<String>();
        for (Database.Error err : errors) {
            errorMessages.add(err.getMessage());
        }

        Event_Log__c failLog = Util_Event.getLog(null, 'S', 'S', 'Subscription25__Contract_Product__c', 'ActivateDraftContractProduct', contractProductId, null, String.valueOf(contractProductId));
        failLog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        failLog.Integration_Status__c = Util_Event.LogEventStatus.CANCELLED.name();
        failLog.Message__c = 'Failed to activate Contract Product ' + contractProductId + ': ' + String.join(errorMessages, '; ');
        return failLog;
    }

    public override void finishBatch(Database.BatchableContext bc){}
}
