Map<String, String> renames = new Map<String, String>{ 'Shipping (NL)' => 'Office (NL)', 'Shipping (UK)' => 'Office (UK)', 'Shipping (GR)' => 'Office (GR)' };
List<Business_Entities__c> bes = [SELECT Id, Business_Hours_Shipping__c FROM Business_Entities__c WHERE Business_Hours_Shipping__c IN :renames.keySet()];
for (Business_Entities__c be : bes) be.Business_Hours_Shipping__c = renames.get(be.Business_Hours_Shipping__c);
update bes;
for (BusinessHours bh : [SELECT Name, TimeZoneSidKey FROM BusinessHours WHERE Name LIKE 'Office (%' OR Name LIKE 'Shipping (%']) System.debug('CHK BH ' + bh.Name + ' ' + bh.TimeZoneSidKey);
for (Business_Entities__c be : [SELECT Reseller__c, Name, Business_Hours_Shipping__c FROM Business_Entities__c ORDER BY Reseller__c]) System.debug('CHK BE ' + be.Reseller__c + ' ' + be.Name + ' -> ' + be.Business_Hours_Shipping__c);
