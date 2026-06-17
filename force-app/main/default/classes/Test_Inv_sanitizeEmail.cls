@isTest
private class Test_Inv_sanitizeEmail {

    @isTest
    static void TestSanitizeEmail() {
        Inv_sanitizeEmail.sanitizeEmailRequests inp1 = new Inv_sanitizeEmail.sanitizeEmailRequests();
        inp1.email = 'jan@klaassen.com';
        list<Inv_sanitizeEmail.sanitizeEmailRequests> inpList1 = new list<Inv_sanitizeEmail.sanitizeEmailRequests>();
        inpList1.add(inp1);
        Inv_sanitizeEmail.sanitizeEmailRequests inp2 = new Inv_sanitizeEmail.sanitizeEmailRequests();
        inp2.email = 'jan+katrein@klaassen.com';
        list<Inv_sanitizeEmail.sanitizeEmailRequests> inpList2 = new list<Inv_sanitizeEmail.sanitizeEmailRequests>();
        inpList2.add(inp2);
        Inv_sanitizeEmail.sanitizeEmailRequests inp3 = new Inv_sanitizeEmail.sanitizeEmailRequests();
        inp3.email = 'katrein@klaassen';
        list<Inv_sanitizeEmail.sanitizeEmailRequests> inpList3 = new list<Inv_sanitizeEmail.sanitizeEmailRequests>();
        inpList3.add(inp3);
        Inv_sanitizeEmail.sanitizeEmailRequests inp4 = new Inv_sanitizeEmail.sanitizeEmailRequests();
        inp4.email = 'katrein+help';
        list<Inv_sanitizeEmail.sanitizeEmailRequests> inpList4 = new list<Inv_sanitizeEmail.sanitizeEmailRequests>();
        inpList4.add(inp4);


        Test.startTest();
        // error sign no document / not ready
        List<Inv_sanitizeEmail.sanitizeEmailResults> resList1 = Inv_sanitizeEmail.sanitizeEmail(inpList1);
        list<Inv_sanitizeEmail.sanitizeEmailResults> resList2 = Inv_sanitizeEmail.sanitizeEmail(inpList2);
        list<Inv_sanitizeEmail.sanitizeEmailResults> resList3 = Inv_sanitizeEmail.sanitizeEmail(inpList3);
        list<Inv_sanitizeEmail.sanitizeEmailResults> resList4 = Inv_sanitizeEmail.sanitizeEmail(inpList4);
        Test.stopTest();


        System.assertEquals('jan@klaassen.com', resList1[0].email);
        System.assertEquals('jan@klaassen.com', resList2[0].email);  
        System.assertEquals('katrein@klaassen', resList3[0].email);  
        System.assertEquals('katrein@', resList4[0].email);
    }

}