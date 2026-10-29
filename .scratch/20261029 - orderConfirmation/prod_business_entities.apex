Map<String,String> bh = new Map<String,String>{'1'=>'Shipping (NL)','3'=>'Shipping (NL)','4'=>'Shipping (NL)','5'=>'Shipping (NL)','6'=>'Shipping (UK)','2'=>'Shipping (GR)'};
List<Business_Entities__c> bes = [SELECT Id, Reseller__c FROM Business_Entities__c];
for (Business_Entities__c be : bes) { be.Business_Hours_Shipping__c = bh.get(be.Reseller__c); be.Shipping_Cutoff_Time__c = Time.newInstance(15,0,0,0); }
update bes;
for (Business_Entities__c be : [SELECT Name, Reseller__c, Business_Hours_Shipping__c, Shipping_Cutoff_Time__c, DealerPortal_Opportunity_AutoProcess__c FROM Business_Entities__c ORDER BY Reseller__c]) System.debug('CHK ' + be.Reseller__c + ' ' + be.Name + ' | ' + be.Business_Hours_Shipping__c + ' | ' + be.Shipping_Cutoff_Time__c + ' | auto ' + be.DealerPortal_Opportunity_AutoProcess__c);
