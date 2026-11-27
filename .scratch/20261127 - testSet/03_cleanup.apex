// TESTSET cleanup (dev/acc ONLY). PATTERN: 'TESTSET %' = all, 'TESTSET C %' / 'TESTSET D %' = filter-test accounts only.
String PATTERN = 'TESTSET %';
// TESTSET cleanup (dev/acc ONLY): removes everything of the test set, in the order from the notes (Order > Invoice > Contract Product > Contract > rest).
if (![SELECT IsSandbox FROM Organization].get(0).IsSandbox) { System.debug('TS_RESULT=NOT A SANDBOX'); return; }
Set<Id> acc = new Map<Id, Account>([SELECT Id FROM Account WHERE Name LIKE :PATTERN]).keySet();
List<Order> ords = [SELECT Id, Status FROM Order WHERE AccountId IN :acc];
for (Order o : ords) { if (o.Status == 'Activated') { o.Status = 'Skip'; } } update ords; delete ords;
delete [SELECT Id FROM Subscription25__Invoice__c WHERE Subscription25__Account__c IN :acc];
delete [SELECT Id FROM Subscription25__Contract_Product__c WHERE Subscription25__Contract__r.AccountId IN :acc];
delete [SELECT Id FROM Contract WHERE AccountId IN :acc];
delete [SELECT Id FROM Asset WHERE AccountId IN :acc AND RecordType.DeveloperName = 'Entity'];
delete [SELECT Id FROM Asset WHERE AccountId IN :acc];
delete [SELECT Id FROM Subscription25__Debtor_Number__c WHERE Subscription25__Account__c IN :acc];
delete [SELECT Id FROM Contact WHERE AccountId IN :acc];
delete [SELECT Id FROM Account WHERE Id IN :acc];
System.debug('TS_RESULT=CLEANED');
