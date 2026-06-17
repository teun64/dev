@isTest
private class Test_Util_Data {

    @isTest
    private static void testUtilOpportunity(){
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        opp.Installation_Notes__c = 'installation notes';
        Database.insert(opp);

        Test.startTest();
        Opportunity opr = Util_Data.getOpportunityForExactSyncById(opp.Id);
        Test.stopTest();

        System.assertEquals(opp.id, opr.id);

    }
    
    //createContentVersion
    @isTest
    private static void testUtilContenVersion(){
        Blob bl = Blob.valueOf('Body Language');
        
        Test.startTest();        
        Contentversion cvi = Util_Data.createContentVersion('Document.txt', bl);
        Database.insert(cvi);
        Test.stopTest();
        
        ContentVersion cvr = [SELECT Id, Title, ContentDocumentId FROM ContentVersion WHERE Id = :cvi.Id LIMIT 1];
        List<ContentDocument> docs = [SELECT Id, Title, LatestPublishedVersionId FROM ContentDocument];
        System.assertEquals(docs.size(), 1);
        System.assertEquals(docs[0].Id, cvr.ContentDocumentId);
        System.assertEquals(docs[0].LatestPublishedVersionId, cvr.Id);
        System.assertEquals(docs[0].Title, cvr.Title);                
    }    


    //createContentVersion
    @isTest
    private static void testUtilContentDocumentLink(){
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);
        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Opportunity opp = Test_Data.createOpportunity(acct.Id, cont.Id, 'test name', false);
        Database.insert(opp);

        Blob bl = Blob.valueOf('Body Language');
        Contentversion cvi = Util_Data.createContentVersion('Document.txt', bl);
        Database.insert(cvi);

        ContentVersion cvr = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cvi.Id LIMIT 1];
        
        Test.startTest();
        ContentDocumentLink cli = Util_Data.createContentDocumentLink(cvr.ContentDocumentId , opp.Id);
        Database.insert(cli);
        Test.stopTest();
        
        System.assertNotEquals(null, cli.id);
        
    }    

}