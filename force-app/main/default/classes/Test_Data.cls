@isTest
public with sharing class Test_Data {
    public static Account createAccount(String name, String extID, String recordTypeDeveloperName, Boolean doDml){

        Account acct = new Account(Name = name);

        acct.VisitingAddress__Street__s = 'Roerdomp 32';
        acct.VisitingAddress__PostalCode__s = '1715 HL';
        acct.VisitingAddress__City__s = 'Spanbroek';
        acct.VisitingAddress__CountryCode__s = 'NL';

        acct.useBillingAddress__c = true;
        acct.useShippingAddress__c = false;

        acct.BillingStreet = 'Postbus 184';
        acct.BillingPostalCode = '1715 ZH';
        acct.BillingCity = 'Spanbroek';
        acct.BillingCountryCode = 'NL';

        acct.ShippingStreet = 'Roerdomp 32';
        acct.ShippingPostalCode = '1715 HL';
        acct.ShippingCity = 'Spanbroek';
        acct.ShippingCountryCode = 'NL';

        acct.Bank_Account__c = Name + ' - Bank';
        acct.Bank_Account_Number__c = 'NL35INGB0666489106';
        acct.Bank_BIC__c = 'INGBNL2A';

        acct.Reseller_Name__c = '1';
        acct.Relation_Type__c = 'End User';
        acct.Sales_Language__c = 'NL';
        acct.Payment_Method_Opportunities__c = '08';
        acct.Payment_Method_Contracts__c = 'p0';
        //if(extID != '99') {
            //acct.Exact_Id__c = 'account_sync_' + extID;
            //acct.Exact_Billing_Address_Id__c = 'address_sync_' + extID;
        //}
        acct.extID_1__c = extID;

        acct.WSONE_DATA__DutchBusinessValidationStatus__c = 'VALIDATED';
        acct.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get(recordTypeDeveloperName).getRecordTypeId();

        if (recordTypeDeveloperName != 'B2C') {
            acct.VAT_Number__c = 'NL370528980B92';
            acct.VAT_Number_Confirmation__c = true;
            acct.CoC_Number__c = '27339223';
            acct.CoC_Number_Confirmation__c = true;
        }

        if(doDml){
            Database.insert(acct);
        }
        return acct;
    }
    public static Account createAccount(String name, Integer extID, String recordTypeDeveloperName, Boolean doDml){
        return createAccount(name, String.valueOf(extID), recordTypeDeveloperName, doDml);
    }
    public static Product2 createProduct(String name, String Code, String extID, String recordTypeDeveloperName, Boolean doDml){
        Product2 pr = new Product2(Name = name, ProductCode = code, extId__c = extID, IsActive = true);
        pr.RecordTypeId = Schema.SObjectType.Product2.getRecordTypeInfosByDeveloperName().get(recordTypeDeveloperName).getRecordTypeId();
        if(doDml){
            Database.insert(pr);
        }
        return pr;
    }

    public static Data_Translation__c createProductTranslation(Id prdId, String language, String name, String description,  Boolean doDml){
        Data_Translation__c dt = new Data_Translation__c(Name__c = name, Language__c = language, Description__c = description, Product__c = prdId);
        if(doDml){
            Database.insert(dt);
        }
        return dt;
    }

    public static Contact createContact(Id acctId, String lastName, String phone, String email, Boolean doDml){
        Contact cont = new Contact(AccountId = acctId, LastName = lastName, Phone = phone, Email = email);

        if(doDml){
            Database.insert(cont);
        }
        return cont;
    }

    public static PricebookEntry createPricebookEntry(Id prodId, Decimal price, Boolean doDml){
        PricebookEntry pbe = new PricebookEntry(Product2Id = prodId, UnitPrice = price);
        pbe.Pricebook2Id = Test.getStandardPricebookId();
        pbe.IsActive = true;
        if(doDml){
            Database.insert(pbe);
        }
        return pbe;
    }

    public static Opportunity createOpportunity(Id acctId, Id salesContactId, String name, Boolean doDml){
        Opportunity opp = new Opportunity(AccountId = acctId, Sales_Contact__c = salesContactId, Name = name);
        opp.StageName = 'Offer';
        opp.CloseDate = Date.today()+14;
        opp.Sales_Channel__c = 'Moving Intelligence';
        opp.Subscriptions_StartDate__c = opp.CloseDate + 7;
        opp.Subscriptions_ContractTerm__c = 36;
        opp.Option_Require_Signature__c = true;
        opp.Option_Show_Activation_Fee_Remark__c = false;
        opp.Option_Show_Compressed__c = true;
        opp.Option_Show_ListPrice__c = true;
        opp.Option_Show_UnitPrice__c = true;
        opp.OfferSkipSignReady__c = Test.isRunningTest();

        if(doDml){
            Database.insert(opp);
        }
        return opp;
    }

    /*public static Quote createQuote(Id oppId, String name, Boolean doDml){
        Quote quo = new Quote(OpportunityId = oppId, Name = name);
        quo.Status = 'Draft';
        quo.ExpirationDate = Date.today().addDays(31);

        if(doDml){
            Database.insert(quo);
        }
        return quo;
    } */

    public static Order createOrder(Id acctId, Id adminId, Date effectiveDate, Boolean doDml){
        Order ord = new Order();
        ord.AccountId = acctId;
        ord.Subscription25__Administration__c = adminId;
        ord.EffectiveDate = effectiveDate;
        ord.Sales_Channel__c = 'Moving Intelligence';
        ord.Status = 'Draft';
        ord.Pricebook2Id = Test.getStandardPricebookId();
        ord.EndDate = effectiveDate.addDays(28);

        if(doDml){
            Database.insert(ord);
        }
        return ord;
    }

    public static OrderItem createOrderItem(Id orderId, Id pbeId, Decimal unitPrice, Boolean doDml){
    	OrderItem ordItem = new OrderItem();
    	ordItem.OrderId = orderId;
    	orditem.PricebookEntryId = pbeId;
    	ordItem.Quantity = 1;
    	ordItem.UnitPrice = unitPrice;

    	if(doDml){
    		Database.insert(ordItem);
    	}
    	return ordItem;
    }

    public static OrderItem createOrderItem2(Id orderId, Id pbeId, Id prdId, Decimal unitPrice, Boolean doDml){
    	OrderItem ordItem = new OrderItem();
    	ordItem.OrderId = orderId;
    	orditem.PricebookEntryId = pbeId;
    	ordItem.Quantity = 1;
    	ordItem.UnitPrice = unitPrice;
        ordItem.Subscription25__Product__c = prdId;
        ordItem.Subscription25__VAT_Percentage__c = 21;
        ordItem.ServiceDate = Date.today().addDays(-14);
        ordItem.EndDate = Date.today().addDays(14);
        ordItem.Subscription25__Hide_VAT_On_Invoice__c = false;

    	if(doDml){
    		Database.insert(ordItem);
    	}
    	return ordItem;
    }

    public static Contract createContract(Id acctId, Id adminId, Boolean doDml){
        Contract cont = new Contract();
        cont.AccountId = acctId;
        cont.Subscription25__Administration__c = adminId;
        cont.Status = 'Draft';
        cont.Pricebook2Id = Test.getStandardPricebookId();
        cont.StartDate = Date.today();
        cont.ContractTerm = 12;
        cont.Subscription25__Invoice_Cycle__c = 1;
        cont.Subscription25__Renewal_Term__c = 12;

        if(doDml){
            Database.insert(cont);
        }
        return cont;
    }

    public static Subscription25__Contract_Product__c createContractProduct(Id contId, Id prodId, Boolean doDml){
        Subscription25__Contract_Product__c contProd = new Subscription25__Contract_Product__c();
        contProd.Subscription25__Contract__c = contId;
        contProd.Subscription25__Product__c = prodId;
        contProd.Subscription25__Quantity__c = 1;
        contProd.Subscription25__Price__c = 100;
        contProd.Subscription25__Start_Date__c = Date.today();

        if(doDml){
            Database.insert(contProd);
        }
        return contProd;
    }

    public static Subscription25__Invoice__c createInvoice(ID admId, Id accId, string Status, Boolean doDml){
        Subscription25__Invoice__c inv = new Subscription25__Invoice__c();
        inv.Subscription25__Administration__c = admId;
        inv.Subscription25__Account__c = accId;
        inv.Subscription25__Payment_Method__c = 'WIRE_TRANSFER';
        inv.Subscription25__Gross_Amount__c = 120;
        inv.Subscription25__Total_Amount__c = 100;
        inv.Subscription25__Sync_State__c = 'COMPLETE';
        //inv.Subscription25__Start_Date__c = Date.today();
        inv.Sales_Channel__c = 'Moving Intelligence';
        inv.Subscription25__Status__c =  Status;
        inv.Subscription25__Invoice_Date__c = Date.today();
        inv.Subscription25__Paid_In_Advance__c = false;
        inv.Subscription25__Email_Status__c = 'SENT';
        inv.Subscription25__Purchase_Order_Number__c = 'TEST';
        inv.Payment_Method__c = 'p0';

        if(doDml){
            Database.insert(inv);
        }
        return inv;
    }

    public static OpportunityLineItem createOpportunityLineItem(Id oppId, Id pbeId, Boolean doDml){
        OpportunityLineItem oli = new OpportunityLineItem(OpportunityId = oppId, PricebookEntryId = pbeId);
        oli.Quantity = 1;
        oli.UnitPrice = 10;
        if(doDml){
            Database.insert(oli);
        }
        return oli;
    }

    public static cadmus_sign2__Sign_request_template__c createSignRequestTemplate(Boolean doDml){
        
        // Create a SignRequestTemplate record
        cadmus_sign2__Sign_request_template__c srt = new cadmus_sign2__Sign_request_template__c();


        srt.name = 'mi - Opportunity - 1 Signer - Owner as Receiver';
        srt.DeveloperName__c = 'mi_Opportunity_1_Signer_Owner_As_Receiver';
        srt.cadmus_sign2__API_Callback_Status_Url__c = null;
        srt.cadmus_sign2__Allow_Inperson_Signing__c = false;
        srt.cadmus_sign2__Allow_Signer_To_Reassign__c = true;
        srt.cadmus_sign2__Allow_Unsigned_Document_Download__c = false;
        srt.cadmus_sign2__Attach_Doc_When_Email_Send_For_Signing__c = false;
        srt.cadmus_sign2__Attach_Signed_Doc_With_Receiver_Email__c = false;
        srt.cadmus_sign2__Attachment_type__c = 'FILES_OVERWRITE';
        //srt.cadmus_sign2__Branding__c = 'a2MAY0000058LVp2AM';
        srt.cadmus_sign2__Certificate_Required__c = false;
        srt.cadmus_sign2__Data_Source__c = null;
        srt.cadmus_sign2__Days_Till_Expired__c = null;
        srt.cadmus_sign2__Digital_Signature_Type__c = 'AATL';
        srt.cadmus_sign2__Disable_Sign_As__c = false;
        //srt.cadmus_sign2__Email_Extra_Merge_Fields_Data_Source__c = 'a2CAY000000jAcj2AE';
        srt.cadmus_sign2__Email_template_prefix__c = 'miButler';
        srt.cadmus_sign2__Enable_Pagination_In_UI__c = false;
        srt.cadmus_sign2__End_signing_redirect_URL__c = null;
        srt.cadmus_sign2__Expiry_Date_DS_Field__c = 'CloseDate';
        //srt.cadmus_sign2__Expiry_Date_DS__c = 'a2CAY000000jAcj2AE';
        srt.cadmus_sign2__FDA__c = false;
        srt.cadmus_sign2__Lookup_field_name__c = 'Name';
        srt.cadmus_sign2__Lookup_object_name__c = 'Opportunity__c';
        srt.cadmus_sign2__Migrated_Customer_Template_Id__c = null;
        srt.cadmus_sign2__Notification_Days_Before_Reminders__c = 4;
        srt.cadmus_sign2__Notification_Reminder_Frequency__c = 2;
        srt.cadmus_sign2__OWA_Id__c = null;
        srt.cadmus_sign2__Sending_User_Data_Source__c = null;
        srt.cadmus_sign2__Set_Email_Activity_Logging_Level__c = null;
        srt.cadmus_sign2__Sign_Request_Url_One_Click_Expiry__c = false;
        srt.cadmus_sign2__Stakeholder_By_Flow__c = null;
        srt.cadmus_sign2__Static_OWA__c = false;
        srt.cadmus_sign2__Suppress_All_Emails__c = false;
        srt.cadmus_sign2__Translation_DataSource__c = null;
        srt.cadmus_sign2__Use_Flow_For_Signer__c = false;
        srt.cadmus_sign2__Use_Form_Fields_From_Template__c = true;
        srt.cadmus_sign2__Warning_Nr_Days_Before_Expiration__c = 3;
        //srt.cadmus_sign2__Customer_Template_Id__c = '00DAY000000TYeD_a2RAY000000HvrV';
        srt.cadmus_sign2__Email_Sender_Overwrite_Class__c = null;
        srt.cadmus_sign2__Org_Wide_Email_Address_Data_Source__c = null;
        srt.cadmus_sign2__Org_Wide_Email_Address_Field__c = null;
        srt.cadmus_sign2__Org_Wide_Email_Address_For_Batch__c = null;

        if (doDml) {
            Database.insert(srt);
        }

        return srt;
    }

    public static OAuth_Token__c createOAuthToken(Boolean doDml){
        OAuth_Token__c token = new OAuth_Token__c();
        token.Client_Id__c = 'id';
        token.Client_Secret__c = 'secret';
        token.Access_Token__c = 'access';
        token.Refresh_Token__c = 'refresh';
        token.Access_Token_Expiration__c = DateTime.now().addHours(12);
        token.Refresh_Token_Expiration__c = DateTime.now().addHours(12);

        if(doDml){
            Database.insert(token);
        }
        return token;
    }

    public static List<Exact_Settings__c> createExactSettings(String adminCode, Boolean doDml){
        List<Exact_Settings__c> setts = new List<Exact_Settings__c>();
        setts.add(new Exact_Settings__c(Name = 'ADMIN_CODE', String_Value__c = adminCode));
        setts.add(new Exact_Settings__c(Name = 'WAREHOUSE_ID', String_Value__c = 'warehouse'));

        if(doDml){
            Database.insert(setts);
        }
        return setts;
    }


    public static List<Account> generateAccounts(Boolean doDml, Integer amount, String recordTypeDeveloperName){
        List<Account> accs = new List<Account>();
        for(Integer i = 0; i < amount; i++){
            Account acc = new Account(
                Name = 'test' + i,
                RecordTypeId = Schema.sObjectType.Account.getRecordTypeInfosByDeveloperName().get(recordTypeDeveloperName).getRecordtypeId(),
                Reseller_Name__c = '1',
                Sales_Language__c = 'NL'
            );

            accs.add(acc);
        }

        if(doDml){
            Database.insert(accs);
        }

        return accs;
    }

    public static List<Opportunity> generateOpportunities(Boolean doDml, Integer amount, Id parentAccId, String stage, Date closeDate){
        List<Opportunity> opps = new List<Opportunity>();
        for(Integer i = 0; i < amount; i++){
            Opportunity opp = new Opportunity(
                Name = 'test' + i,
                AccountId = parentAccId,
                StageName = stage,
                CloseDate = closeDate
            );

            opps.add(opp);
        }

        if(doDml){
            Database.insert(opps);
        }

        return opps;
    }

    public static Subscription25__Administration__c createAdministration(Boolean doDml){
        Subscription25__Administration__c admin = new Subscription25__Administration__c();
        admin.Name = 'Test';
        admin.Subscription25__Billing_Country__c = 'NL';
        admin.Subscription25__Invoice_Number_Prefix__c = 'TTT';
        admin.Reseller__c = '1';
        admin.External_ID__c = 1;
        admin.Subscription25__Active__c = True;
        admin.Subscription25__Synchronisation__c = 'Exact';
        admin.Subscription25__Named_Credential__c = 'Exact_NL';
        admin.Subscription25__Twinfield_Company_Code__c = '1234509876';
        admin.Offer_Term_1__c = true;
        admin.Offer_Term_2__c = true;
        admin.Date_New_Branding__c = Date.today().addMonths(-12);
        admin.Invoice_General_Remark__c = true;

        if(doDml){
            Database.insert(admin);
        }
        return admin;
    }

    public static Subscription25__Administration_Product__c createAdministrationProduct(Id adminId, Id prodId, Id vatRateId, Boolean doDml){
        Subscription25__Administration_Product__c adminProd  = new Subscription25__Administration_Product__c();
        adminProd.Subscription25__Administration__c = adminId;
        adminProd.Subscription25__Product__c = prodId;
        adminProd.Subscription25__VATRate__c = vatRateId;

        if(doDml){
            Database.insert(adminProd);
        }
        return adminProd;
    }

    public static Subscription25__VATRate__c createVATRate(String name, Decimal rate, Boolean def, Boolean doDml){
        Subscription25__VATRate__c vatRate = new Subscription25__VATRate__c();
        vatRate.Name = name;
        vatRate.Subscription25__VAT_Percentage__c = rate;
        vatRate.Subscription25__Default__c = def;

        if(doDml){
            Database.insert(vatRate);
        }
        return vatRate;
    }

    public static Subscription25__Debtor_Number__c createDebtorNumber(Id adminId, Id acctId, Boolean doDml){
    	Subscription25__Debtor_Number__c debNr = new Subscription25__Debtor_Number__c();
    	debNr.Subscription25__Administration__c = adminId;
    	debNr.Subscription25__Account__c = acctId;
    	debNr.Subscription25__Debtor_Number__c = 'tst';

    	if(doDml){
    		Database.insert(debNr);
    	}
    	return debNr;
    }

    public static Product_Discount__c createProductDiscount(Id prodId, Id acctId, Boolean doDml){
    	Product_Discount__c prodDis = new Product_Discount__c();
    	prodDis.Account__c = acctId;
    	prodDis.Product__c = prodId;
        prodDis.Status__c = 'Activated';
        prodDis.IsActive__c = true;
        prodDis.From_Quantity_1__c = 1;
    	prodDis.From_Discount_1__c = 0.5;
        prodDis.From_Quantity_2__c = 5;
    	prodDis.From_Discount_2__c = 0.6;
        prodDis.From_Quantity_3__c = 10;
    	prodDis.From_Discount_3__c = 0.8;
        prodDis.From_Quantity_4__c = 25;
    	prodDis.From_Discount_4__c = 0.9;
    	if(doDml){
    		Database.insert(prodDis);
    	}
    	return prodDis;
    }
    public static Case createCase(Account caseAccount, Boolean doDML) {
        Case testCase = new Case(
                Subject = 'Test Case',
                AccountId = caseAccount?.Id,
                Origin = 'Email'
        );
        if(doDML) {
            insert testCase;
        }
        return testCase;
    }

    private static User IntegrationUser;
    public static User getIntegrationUser() {
        if (Test_Data.IntegrationUser == null) {
            Profile integrationProfile = [
                SELECT Id
                FROM Profile
                WHERE Name = 'miAPIIntegration'
            ];
            Test_Data.IntegrationUser = new User(
                Alias = 'testint', Email='integrationusers@movingintelligence.nl.test',
                EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US',
                LocaleSidKey='en_US', ProfileId = integrationProfile.Id,
                TimeZoneSidKey='America/Los_Angeles', UserName='integrationusers@movingintelligence.nl.test'
            );
            PermissionSet permission = [
                SELECT Id
                FROM PermissionSet
                WHERE Name = 'ps_miAPISystemIntegration'
            ];

            System.runAs(new User(Id = UserInfo.getUserId())) {
                Database.insert(Test_Data.IntegrationUser);
                Database.insert(new PermissionSetAssignment(
                    AssigneeId = Test_Data.IntegrationUser.Id,
                    PermissionSetId = permission.Id
                ));
            }
        }
        return Test_Data.IntegrationUser;
    }
}