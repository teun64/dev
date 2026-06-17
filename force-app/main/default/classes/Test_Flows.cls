@isTest
private class Test_Flows {
    @isTest
    private static void testDoFlow(){
        Account acc = Test_Data.createAccount('Test', 11, 'B2B', true);
 
 
       Util_Flows.FlowInputs FI = new Util_Flows.FlowInputs();
       
        FI.flowName = 'afl_Account_Unit_testing';
        FI.recordID = acc.Id;       
        
        Test.startTest();
        Util_Flows.doFlow2(new List<Util_Flows.FlowInputs> {FI});
        Test.stopTest();

        Account act = [SELECT Id, Reseller_Name__c FROM Account WHERE Id = :acc.Id];
        System.assertEquals(acc.Id, act.Id);       
        System.assertEquals(act.Reseller_Name__c, '4' );       
    }
  }