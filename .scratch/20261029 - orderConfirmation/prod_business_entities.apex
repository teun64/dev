Map<String,String> bh = new Map<String,String>{'1'=>'Office (NL)','3'=>'Office (NL)','4'=>'Office (NL)','5'=>'Office (NL)','6'=>'Office (UK)','2'=>'Office (GR)'};
List<Business_Entities__c> bes = [SELECT Id, Reseller__c FROM Business_Entities__c];
for (Business_Entities__c be : bes) { be.Business_Hours_Shipping__c = bh.get(be.Reseller__c); be.Shipping_Cutoff_Time__c = Time.newInstance(15,0,0,0); }
update bes;
for (Business_Entities__c be : [SELECT Name, Reseller__c, Business_Hours_Shipping__c, Shipping_Cutoff_Time__c, DealerPortal_Opportunity_AutoProcess__c FROM Business_Entities__c ORDER BY Reseller__c]) System.debug('CHK ' + be.Reseller__c + ' ' + be.Name + ' | ' + be.Business_Hours_Shipping__c + ' | ' + be.Shipping_Cutoff_Time__c + ' | auto ' + be.DealerPortal_Opportunity_AutoProcess__c);
