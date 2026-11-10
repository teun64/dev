// Prod data step BEFORE the CMDT JobDispatcherStep.Day_CardExpiryCheck deploy: the Day dispatcher needs this record,
// otherwise startStep throws and every later Day step is skipped. Idempotent.
// Run: sf apex run -o prod -f ".scratch/20261109 - paymentDunning/sub25_record.apex" | grep CHECK
List<Subscription25__Schedulable_Class__c> existing = [SELECT Id FROM Subscription25__Schedulable_Class__c WHERE Name = 'Batch_CardExpiryCheck'];
if (existing.isEmpty()) {
    insert new Subscription25__Schedulable_Class__c(Name = 'Batch_CardExpiryCheck', Subscription25__Unique_Name__c = 'Batch_CardExpiryCheck');
    System.debug('CHECK Sub25 record created');
} else {
    System.debug('CHECK Sub25 record already there: ' + existing[0].Id);
}
System.debug('CHECK open card payments (first expiry run reads these cards from Stripe): '
    + [SELECT COUNT() FROM Payment__c WHERE Type__c IN ('psp-recurring', 'psp-dd') AND Status__c = 'New' AND Collection_Date__c > TODAY
        AND Account__r.PayProv_PaymentMethodType__c = 'card' AND Account__r.PayProv_PaymentMethodId__c != null]);
