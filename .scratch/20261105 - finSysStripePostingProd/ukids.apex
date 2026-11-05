Map<Id, Subscription25__Invoice__c> invs = new Map<Id, Subscription25__Invoice__c>([SELECT Id FROM Subscription25__Invoice__c WHERE Subscription25__Invoice_Number__c IN ('GB26754787','GB26755137')]);
List<Event_Log__c> logs = new List<Event_Log__c>();
Set<String> ncs = new Set<String>();
List<Subscription25__Invoice__c> changed = Util_FinancialSystem_Invoice.loadFinSysIds(invs.keySet(), logs, ncs);
for (Subscription25__Invoice__c i : changed) System.debug('INV ' + i.Id + ' ' + i.FinSysInvoiceId__c + ' ' + i.FinSysInvoiceNumber__c);
for (Event_Log__c l : logs) System.debug('LOG ' + String.valueOf(l).left(400));
if (!changed.isEmpty()) for (Database.SaveResult r : Util_FinancialSystem_Invoice.saveInvoices(changed)) System.debug('SAVE ' + r.isSuccess() + ' ' + r.getErrors());
Util_FinancialSystem.saveLimits();
