@isTest
private class Test_Inv_signOpportunityOffer {

    @isTest
    private static void testSignOpportunityOffer (){
        Subscription25__Administration__c admin = Test_Data.createAdministration(true);
		Subscription25__VATRate__c vr = Test_Data.createVATRate('9%', 9, true, true);
        Account acct = Test_Data.createAccount('Test', '12', 'B2B', true);

        Contact cont = Test_Data.createContact(acct.Id, 'Test', '1234567890', 'lex@gen25.com', true);
        Opportunity opp1 = Test_Data.createOpportunity(acct.id, cont.id, 'testSignOpportunityOffer1', true);
        Opportunity opp2 = Test_Data.createOpportunity(acct.id, cont.id, 'testSignOpportunityOffer2', false);
        Opportunity opp3 = Test_Data.createOpportunity(acct.id, cont.id, 'testSignOpportunityOffer3', false);
        String docTitle = Util_System.sanitizeFileName(opp2.Name) + '.pdf';

        ContentVersion insContVer = new ContentVersion(
            ContentLocation = 'S', // S = Stored in Salesforce
            PathOnClient = docTitle,
            Title = docTitle,
            VersionData = Blob.valueOf('test')
        );
        Database.insert(insContVer);

        ContentVersion contVer = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :insContVer.Id];

        opp2.OfferVersionId__c = contVer.Id;
        opp2.OfferDocumentId__c = contVer.ContentDocumentId;
        opp2.OfferDocumentTitle__c = docTitle;
        Database.insert(opp2);

        opp3.Sales_Channel__c = 'Echoes';
        opp3.OfferVersionId__c = contVer.Id;
        opp3.OfferDocumentId__c = contVer.ContentDocumentId;
        opp3.OfferDocumentTitle__c = docTitle;
        Database.insert(opp3);

        cadmus_sign2__Sign_request_template__c srt = Test_Data.createSignRequestTemplate(true);
        
        Inv_signOpportunityOffer.signOpportunityOfferRequests inp1 = new Inv_signOpportunityOffer.signOpportunityOfferRequests();
        inp1.opportunityId = opp1.Id;
        list<Inv_signOpportunityOffer.signOpportunityOfferRequests> inpList1 = new list<Inv_signOpportunityOffer.signOpportunityOfferRequests>();
        inpList1.add(inp1);
        Inv_signOpportunityOffer.signOpportunityOfferRequests inp2 = new Inv_signOpportunityOffer.signOpportunityOfferRequests();
        inp2.opportunityId = opp2.Id;
        list<Inv_signOpportunityOffer.signOpportunityOfferRequests> inpList2 = new list<Inv_signOpportunityOffer.signOpportunityOfferRequests>();
        inpList2.add(inp2);
        Inv_signOpportunityOffer.signOpportunityOfferRequests inp3 = new Inv_signOpportunityOffer.signOpportunityOfferRequests();
        inp3.opportunityId = opp3.Id;
        list<Inv_signOpportunityOffer.signOpportunityOfferRequests> inpList3 = new list<Inv_signOpportunityOffer.signOpportunityOfferRequests>();
        inpList3.add(inp3);

        Test.startTest();
        // error sign no document / not ready
        List<Inv_signOpportunityOffer.signOpportunityOfferResults> resultMessages1 = Inv_signOpportunityOffer.signOpportunityOffer(inpList1);
        list<Inv_signOpportunityOffer.signOpportunityOfferResults> resultMessages2 = Inv_signOpportunityOffer.signOpportunityOffer(inpList2);
        list<Inv_signOpportunityOffer.signOpportunityOfferResults> resultMessages3 = Inv_signOpportunityOffer.signOpportunityOffer(inpList3);
        Test.stopTest();

        //system.assertEquals(insContVer.ContentDocumentId, contVer.ContentDocumentId);
        system.assertEquals(docTitle, contVer.Title);
        // error sign no document / not ready
        //System.assertEquals('false', String.valueOf(opp1.OfferSignReady__c));
        System.assertEquals('Error: This opportunity ' + Opp1.Name + ' is not ready to be signed. (' + opp1.Id + ')', resultMessages1[0].resultMessage);      
        //System.assertEquals('true', String.valueOf(opp2.OfferSignReady__c));
        System.assertEquals('Success: ' + opp2.OfferDocumentTitle__c + ' has been successfully added to the signing queue. (' + opp2.Id + ')', resultMessages2[0].resultMessage);
        //System.assertEquals('true', String.valueOf(opp3.OfferSignReady__c));
        System.assertEquals('Error: Template echoes_Opportunity_1_Signer_Owner_As_Receiver not found, signing not possible. (' + opp3.Id + ')', resultMessages3[0].resultMessage);        
    }
}