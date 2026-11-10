// READ-ONLY check of the dunning cycle after go-live. Nothing is written.
// Run: sf apex run -o prod -f ".scratch/20261109 - paymentDunning/dunning_monitor.apex" | grep CHECK
// 1. every payment in the cycle (step, dates, code, action)
for (Payment__c p : [
    SELECT Name, Status__c, Type__c, Dunning_Step__c, Dunning_Action__c, Failure_Code__c, Retry_Date__c, Suspension_Date__c,
           Account__r.Name, Account__r.Reseller_Name__c, Account__r.PayProv_PaymentMethodType__c, LastModifiedDate
    FROM Payment__c WHERE Dunning_Step__c != null ORDER BY LastModifiedDate DESC LIMIT 50
]) {
    System.debug('CHECK cycle ' + p.Name + ' | ' + p.Account__r?.Name + ' (reseller ' + p.Account__r?.Reseller_Name__c + ', ' + p.Account__r?.PayProv_PaymentMethodType__c + ')'
        + ' | status=' + p.Status__c + ' step=' + p.Dunning_Step__c + ' action=' + p.Dunning_Action__c + ' code=' + p.Failure_Code__c
        + ' retry=' + p.Retry_Date__c + ' suspension=' + p.Suspension_Date__c + ' modified=' + p.LastModifiedDate.format('yyyy-MM-dd HH:mm'));
}
// 2. failures since go-live that did NOT enter the cycle (should only be setup/page failures or configuration errors)
for (Payment__c p : [
    SELECT Name, Status__c, Type__c, Account__r.Name FROM Payment__c
    WHERE Status__c IN ('Failed', 'Reversed') AND Dunning_Step__c = null AND LastModifiedDate >= 2026-11-10T16:00:00Z
    ORDER BY LastModifiedDate DESC LIMIT 20
]) System.debug('CHECK outside cycle ' + p.Name + ' ' + p.Status__c + ' ' + p.Type__c + ' | ' + p.Account__r?.Name);
// 3. payment Cases since go-live (only "Suspend service" and configuration / charged-twice Cases expected)
for (Case c : [
    SELECT CaseNumber, Subject, Owner.Name, Status, CreatedDate FROM Case
    WHERE CreatedDate >= 2026-11-10T16:00:00Z AND (Subject LIKE '%payment%' OR Subject LIKE 'Direct Debit%' OR Subject LIKE 'Card payment%')
    ORDER BY CreatedDate DESC LIMIT 20
]) System.debug('CHECK case ' + c.CaseNumber + ' | ' + c.Subject + ' | owner ' + c.Owner.Name + ' | ' + c.Status + ' | ' + c.CreatedDate.format('yyyy-MM-dd HH:mm'));
// 4. dunning mails sent since go-live (EmailMessage linked to the payment)
Map<String, Integer> mails = new Map<String, Integer>();
for (EmailMessage m : [
    SELECT Subject FROM EmailMessage WHERE CreatedDate >= 2026-11-10T16:00:00Z
    AND RelatedToId IN (SELECT Id FROM Payment__c WHERE Dunning_Step__c != null) LIMIT 500
]) mails.put(m.Subject, (mails.containsKey(m.Subject) ? mails.get(m.Subject) : 0) + 1);
for (String k : mails.keySet()) System.debug('CHECK mail ' + mails.get(k) + 'x ' + k);
// 5. card expiry run
System.debug('CHECK card renewal requested (open payments): ' + [SELECT COUNT() FROM Payment__c WHERE Card_Renewal_Requested__c != null AND Status__c = 'New']);
