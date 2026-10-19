/**
 * Terminates Closed contracts whose termination date has passed in administrations excluded from the Subscription25 jobs
 * (Subscription25__Exclude_From_Jobs__c, e.g. Greece (G4S): no financial system connection). Job_ContractManagement skips
 * these administrations, so a termination that arrives with a future date stays Closed for good.
 * Only the contract status changes: Subscription25 then terminates the contract products itself, the same as it does
 * when the platform sends a termination with a date in the past.
 */
global class Batch_TerminateExcludedAdminContracts extends Subscription25.Job_AbstractBatch2 implements Util_JobDispatcher.Step {

    private static final AccessLevel RUNNING_MODE = AccessLevel.SYSTEM_MODE;

    // set when started by Batch_JobDispatcher: finishBatch then starts the dispatcher's next step
    private String dispatcher;

    // contracts ending before this date are expired: today. Subscription25 itself terminates a contract on any save with a
    // termination date in the past, so a test can only build the Closed state with a date from today; a test run checks
    // 7 days ahead
    private Date checkDate = Test.isRunningTest() ? Date.today().addDays(7) : Date.today();

    public void setDispatcher(String dispatcher) {
        this.dispatcher = dispatcher;
    }

    global Batch_TerminateExcludedAdminContracts() {
        super('Batch_TerminateExcludedAdminContracts');
    }

    public override Integer getBatchSize() {
        return 50;
    }

    public override Database.QueryLocator startBatch(Database.BatchableContext bc){
        String query =
            'SELECT Id ' +
            'FROM Contract ' +
            'WHERE Status = \'Closed\' ' +
            'AND Subscription25__Termination_Date__c < :checkDate ' +
            'AND Subscription25__Administration__r.Subscription25__Exclude_From_Jobs__c = true';
        return Database.getQueryLocatorWithBinds(query, new Map<String, Object>{ 'checkDate' => this.checkDate }, AccessLevel.SYSTEM_MODE);
    }

    public override void executeBatch(Database.BatchableContext bc, List<SObject> scope){
        List<Contract> toTerminate = new List<Contract>();
        for (Contract contr : (List<Contract>) scope) {
            toTerminate.add(new Contract(Id = contr.Id, Status = 'Terminated'));
        }

        //partial success (not all-or-none) - one contract failing must not keep the others in the chunk Closed
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

    private Event_Log__c buildFailureLog(Id contractId, List<Database.Error> errors){
        List<String> errorMessages = new List<String>();
        for (Database.Error err : errors) {
            errorMessages.add(err.getMessage());
        }

        Event_Log__c failLog = Util_Event.getLog(null, 'S', 'S', 'Contract', 'TerminateExcludedAdminContract', contractId, null, String.valueOf(contractId));
        failLog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
        failLog.Integration_Status__c = Util_Event.LogEventStatus.CANCELLED.name();
        failLog.Message__c = 'Failed to terminate Contract ' + contractId + ': ' + String.join(errorMessages, '; ');
        return failLog;
    }

    public override void finishBatch(Database.BatchableContext bc){
        Util_JobDispatcher.startNext(this.dispatcher, 'Batch_TerminateExcludedAdminContracts');
    }
}
