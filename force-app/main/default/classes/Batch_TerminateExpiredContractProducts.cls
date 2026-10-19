/**
 * Terminates Closed Partner code contract products whose own termination date has passed, while their contract keeps running.
 * Job_ContractManagement (Subscription25) did this itself until the package upgrade of 2026-01-06; since then
 * these lines stay Closed. Left Closed, Rest_UpsertContract picks them up on a
 * later contract termination and moves their termination date (and correction) to the contract's date.
 * Only Partner code products (Product2.Is_Partner_Code__c, the discount line Rest_UpsertContract adds for the first period),
 * and only the status changes, the same as the package job did: Closed -> Terminated.
 *   A: contract Activated without a termination date
 *   B: contract Closed with a termination date later than the contract product's
 * Contract products on a Terminated contract, or on a Closed contract ending on or before them, are left to the package.
 */
global class Batch_TerminateExpiredContractProducts extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {

    private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    // contract products ending before this date are expired. Subscription25 itself terminates a contract product that is
    // saved Closed with a termination date in the past, so a test can only build the Closed state with today's date and
    // then runs the batch as of tomorrow
    @TestVisible
    private Date referenceDate = Date.today();

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_TerminateExpiredContractProducts() {
        super('Batch_TerminateExpiredContractProducts');
    }

    public override Integer getBatchSize() {
        return 100;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc){
        //SOQL can't compare two fields, so case B (contract date later than the contract product's) is checked in executeBatch
        String query =
            'SELECT Id, Subscription25__Termination_Date__c, Subscription25__Contract__r.Status, Subscription25__Contract__r.Subscription25__Termination_Date__c ' +
            'FROM Subscription25__Contract_Product__c ' +
            'WHERE Subscription25__Status__c = \'Closed\' ' +
            'AND Subscription25__Product__r.Is_Partner_Code__c = true ' +
            'AND Subscription25__Termination_Date__c < :referenceDate ' +
            'AND ((Subscription25__Contract__r.Status = \'Activated\' AND Subscription25__Contract__r.Subscription25__Termination_Date__c = null) ' +
            'OR (Subscription25__Contract__r.Status = \'Closed\' AND Subscription25__Contract__r.Subscription25__Termination_Date__c != null))';
        return Database.getQueryLocatorWithBinds(query, new Map<String, Object>{ 'referenceDate' => this.referenceDate }, AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
        List<Subscription25__Contract_Product__c> toTerminate = new List<Subscription25__Contract_Product__c>();
        for (Subscription25__Contract_Product__c cp : (List<Subscription25__Contract_Product__c>) scope) {
            if (Batch_TerminateExpiredContractProducts.isExpired(cp, this.referenceDate)) {
                toTerminate.add(new Subscription25__Contract_Product__c(Id = cp.Id, Subscription25__Status__c = 'Terminated'));
            }
        }

        if (toTerminate.isEmpty()) {
            return;
        }

        //partial success (not all-or-none) - one contract product failing must not keep the others in the chunk Closed
        List<Event_Log__c> toLog = new List<Event_Log__c>();
        List<Database.SaveResult> saveResults = Database.update(toTerminate, false, RUNNING_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (!saveResults[i].isSuccess()) {
                toLog.add(buildFailureLog(toTerminate[i].Id, saveResults[i].getErrors()));
            }
        }
        if (!toLog.isEmpty()) {
            Database.insert(toLog, false, RUNNING_MODE);
        }
    }

    @TestVisible
    private static Boolean isExpired(Subscription25__Contract_Product__c cp, Date referenceDate) {
        Contract contr = cp.Subscription25__Contract__r;
        if ((cp.Subscription25__Termination_Date__c == null) || (cp.Subscription25__Termination_Date__c >= referenceDate) || (contr == null)) {
            return false;
        }
        if (contr.Status == 'Activated') {
            return (contr.Subscription25__Termination_Date__c == null);
        }
        if (contr.Status == 'Closed') {
            return ((contr.Subscription25__Termination_Date__c != null) && (contr.Subscription25__Termination_Date__c > cp.Subscription25__Termination_Date__c));
        }
        return false;
    }

    private Event_Log__c buildFailureLog(Id contractProductId, List<Database.Error> errors){
        List<String> errorMessages = new List<String>();
        for (Database.Error err : errors) {
            errorMessages.add(err.getMessage());
        }

        Event_Log__c failLog = Util_Event.getLog(null, 'S', 'S', 'Subscription25__Contract_Product__c', 'TerminateExpiredContractProduct', contractProductId, null, String.valueOf(contractProductId));
        failLog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        failLog.Integration_Status__c = Util_Event.LogEventStatus.CANCELLED.name();
        failLog.Message__c = 'Failed to terminate Contract Product ' + contractProductId + ': ' + String.join(errorMessages, '; ');
        return failLog;
    }

    public override void finishBatch(Database.BatchableContext bc){
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_TerminateExpiredContractProducts');
    }
}
