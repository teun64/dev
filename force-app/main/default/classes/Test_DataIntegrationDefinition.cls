public with sharing class Test_DataIntegrationDefinition {

    public static void createFinancialSystemContactSyncDefinitions() {
        // Create integration definition
        Integration_Definition__c def = Test_DataIntegrationDefinition.createIntegrationDefinition('Financial System - Contact Sync');
        Database.insert(def);

        // Add events (processes) to definition
        List<Integration_Event__c> events = new List<Integration_Event__c> {
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 10, Logger2.LOGGING_TYPE.Process, 'Sync Contact', 'Apex', 'Util_FinancialSystemCallables.ContactPersonSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 20, Logger2.LOGGING_TYPE.Process, 'Update Account Contact Relation', 'Apex', 'Util_FinancialSystemCallables.UpsertRecord')
        };
        Database.insert(events);

        // Map by Name for easy field mapping
        Map<String, Integration_Event__c> eventMap = new Map<String, Integration_Event__c>();
        for (Integration_Event__c event : events) {
            eventMap.put(event.Name, event);
        }

        // Add fields to the flow events
        List<Event_Field__c> fields = new List<Event_Field__c> {
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'record', 'contactPerson', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createStaticEventField(eventMap.get('Sync Contact').Migration_Id__c, 'doContactSync', 'syncContact', 'Boolean', 'true'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Update Account Contact Relation').Migration_Id__c, 'record', 'record', 'SObject', 'Input')
        };
        Database.insert(fields);
    }

    public static void createFinancialSystemAccountSyncDefinitions() {
        // Create integration definition
        Integration_Definition__c def = Test_DataIntegrationDefinition.createIntegrationDefinition('Financial System - Account Sync');
        Database.insert(def);

        // Add events (processes) to definition
        List<Integration_Event__c> events = new List<Integration_Event__c> {
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 1, Logger2.LOGGING_TYPE.Process, 'Validate Requirements', 'Flow', 'Event_Validate_Account_Sync_Requirements'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 10, Logger2.LOGGING_TYPE.Process, 'Sync Account', 'Apex', 'Util_FinancialSystemCallables.AccountSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 20, Logger2.LOGGING_TYPE.Process, 'Sync Contact', 'Apex', 'Util_FinancialSystemCallables.ContactPersonSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 30, Logger2.LOGGING_TYPE.Process, 'Sync Shipping Address', 'Apex', 'Util_FinancialSystemCallables.ShippingAddressSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 40, Logger2.LOGGING_TYPE.Process, 'Sync Billing Address', 'Apex', 'Util_FinancialSystemCallables.BillingAddressSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 50, Logger2.LOGGING_TYPE.Process, 'Sync Visiting Address', 'Apex', 'Util_FinancialSystemCallables.VisitingAddressSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 60, Logger2.LOGGING_TYPE.Process, 'Sync Bank Account', 'Apex', 'Util_FinancialSystemCallables.BankAccountSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 70, Logger2.LOGGING_TYPE.Process, 'Sync Bank Mandate', 'Apex', 'Util_FinancialSystemCallables.MandateSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 80, Logger2.LOGGING_TYPE.Process, 'Get Debtor Number', 'Apex', 'Util_FinancialSystemCallables.GetDebtorNumber'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 100, Logger2.LOGGING_TYPE.Process, 'Save Records', 'Flow', 'Event_Upsert_FinancialSystem_Account_Sync_Records')
        };
        Database.insert(events);

        // Map by Name for easy field mapping
        Map<String, Integration_Event__c> eventMap = new Map<String, Integration_Event__c>();
        for (Integration_Event__c event : events) {
            eventMap.put(event.Name, event);
        }

        // Add fields to the flow events
        List<Event_Field__c> fields = new List<Event_Field__c> {
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncAccount', 'syncAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncVisitingAddress', 'syncVisitingAddress', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncBillingAddress', 'syncBillingAddress', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncShippingAddress', 'syncShippingAddress', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncMandate', 'syncMandate', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncContact', 'syncContact', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncBankAccount', 'syncBankAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Account').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Account').Migration_Id__c, 'syncAccount', 'syncAccount', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Account').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'syncContact', 'syncContact', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'saveContactPerson', 'saveContactPerson', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Shipping Address').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Shipping Address').Migration_Id__c, 'syncShippingAddress', 'syncShippingAddress', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Shipping Address').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Billing Address').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Billing Address').Migration_Id__c, 'syncBillingAddress', 'syncBillingAddress', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Billing Address').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Visiting Address').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Visiting Address').Migration_Id__c, 'syncVisitingAddress', 'syncVisitingAddress', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Visiting Address').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Account').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Account').Migration_Id__c, 'syncBankAccount', 'syncBankAccount', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Account').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Mandate').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Mandate').Migration_Id__c, 'syncMandate', 'syncMandate', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Bank Mandate').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Debtor Number').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Debtor Number').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveAccount', 'saveAccount', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveContactPerson', 'saveContactPerson', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'record', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Input')
        };
        Database.insert(fields);
    }

    public static void createFinancialSystemOrderSyncDefinitions() {
        // Create integration definition
        Integration_Definition__c def = Test_DataIntegrationDefinition.createIntegrationDefinition('Financial System - Order Sync');
        Database.insert(def);

        // Add events (processes) to definition
        List<Integration_Event__c> events = new List<Integration_Event__c> {
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 1, Logger2.LOGGING_TYPE.Process, 'Validate Requirements', 'Flow', 'Event_Validate_Order_Sync_Requirements'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 10, Logger2.LOGGING_TYPE.Process, 'Sync Contact', 'Apex', 'Util_FinancialSystemCallables.ContactPersonSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 20, Logger2.LOGGING_TYPE.Process, 'Get FinancialSystem Product Ids', 'Apex', 'Util_FinancialSystemCallables.GetProductIdsFinancialSystem'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 30, Logger2.LOGGING_TYPE.Process, 'Sync Order', 'Apex', 'Util_FinancialSystemCallables.OrderSync'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 40, Logger2.LOGGING_TYPE.Process, 'Get Sales Order Lines', 'Apex', 'Util_FinancialSystemCallables.GetSalesOrderLines'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 50, Logger2.LOGGING_TYPE.Process, 'Save Records', 'Flow', 'Event_Upsert_FinancialSystem_Order_Sync_Records')
        };
        Database.insert(events);

        // Map by Name for easy field mapping
        Map<String, Integration_Event__c> eventMap = new Map<String, Integration_Event__c>();
        for (Integration_Event__c event : events) {
            eventMap.put(event.Name, event);
        }

        // Add fields to the flow events
        List<Event_Field__c> fields = new List<Event_Field__c> {
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'record', 'orderRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncContact', 'syncContact', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'syncOrder', 'syncOrder', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'syncContact', 'syncContact', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Contact').Migration_Id__c, 'saveContactPerson', 'saveContactPerson', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get FinancialSystem Product Ids').Migration_Id__c, 'record', 'orderRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get FinancialSystem Product Ids').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get FinancialSystem Product Ids').Migration_Id__c, 'orderItems', 'orderItems', 'List<SObject>', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get FinancialSystem Product Ids').Migration_Id__c, 'adminProducts', 'adminProducts', 'List<SObject>', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get FinancialSystem Product Ids').Migration_Id__c, 'saveAdminProducts', 'saveAdminProducts', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'syncOrder', 'syncOrder', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'record', 'orderRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'adminProducts', 'adminProducts', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Sync Order').Migration_Id__c, 'saveOrder', 'saveOrder', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'record', 'orderRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'orderItems', 'orderItems', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'adminProducts', 'adminProducts', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'contractProducts', 'contractProducts', 'List<SObject>', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'saveOrderItems', 'saveOrderItems', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Sales Order Lines').Migration_Id__c, 'saveContractProducts', 'saveContractProducts', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'record', 'orderRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'accountRecord', 'accountRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'contactPerson', 'contactPerson', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'orderItems', 'orderItemUpdates', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'adminProducts', 'adminProductUpdates', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'contractProducts', 'contractProductUpdates', 'List<SObject>', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveOrder', 'saveOrder', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveContactPerson', 'saveContactPerson', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveOrderItems', 'saveOrderItems', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveAdminProducts', 'saveAdminProducts', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveContractProducts', 'saveContractProducts', 'Boolean', 'Input')
        };
        Database.insert(fields);
    }

    public static void createFinancialSystemFinalizeInvoiceDefinitions() {
        // Create integration definition
        Integration_Definition__c def = Test_DataIntegrationDefinition.createIntegrationDefinition('Financial System - Finalize Invoice');
        Database.insert(def);

        // Add events (processes) to definition
        List<Integration_Event__c> events = new List<Integration_Event__c> {
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 1, Logger2.LOGGING_TYPE.Process, 'Validate Requirements', 'Flow', 'Event_Validate_Invoice_Sync_Requirements'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 10, Logger2.LOGGING_TYPE.Process, 'Finalize Invoice', 'Apex', 'Util_FinancialSystemCallables.FinalizeInvoice'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 20, Logger2.LOGGING_TYPE.Process, 'Get Invoice Details', 'Apex', 'Util_FinancialSystemCallables.GetInvoiceDetails'),
            Test_DataIntegrationDefinition.createIntegrationEvent(def.Migration_Id__c, 100, Logger2.LOGGING_TYPE.Process, 'Save Records', 'Flow', 'Event_Upsert_FinancialSystem_Finalize_Invoice')
        };
        Database.insert(events);

        // Map by Name for easy field mapping
        Map<String, Integration_Event__c> eventMap = new Map<String, Integration_Event__c>();
        for (Integration_Event__c event : events) {
            eventMap.put(event.Name, event);
        }

        // Add fields to the flow events
        List<Event_Field__c> fields = new List<Event_Field__c> {
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'record', 'invoiceRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'finalizeInvoice', 'finalizeInvoice', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Validate Requirements').Migration_Id__c, 'getInvoiceDetails', 'getInvoiceDetails', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Finalize Invoice').Migration_Id__c, 'record', 'invoice', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Finalize Invoice').Migration_Id__c, 'finalizeInvoice', 'finalizeInvoice', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Finalize Invoice').Migration_Id__c, 'saveInvoice', 'saveInvoice', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Invoice Details').Migration_Id__c, 'record', 'invoice', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Invoice Details').Migration_Id__c, 'getInvoiceDetails', 'getInvoiceDetails', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Invoice Details').Migration_Id__c, 'saveInvoice', 'saveInvoice', 'Boolean', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Get Invoice Details').Migration_Id__c, 'saveInvoice', 'saveInvoice', 'Boolean', 'Output'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'record', 'invoiceRecord', 'SObject', 'Input'),
            Test_DataIntegrationDefinition.createEventField(eventMap.get('Save Records').Migration_Id__c, 'saveInvoice', 'saveInvoice', 'Boolean', 'Input')
        };
        Database.insert(fields);
    }

    public static Integration_Definition__c createIntegrationDefinition(String name) {
        Integration_Definition__c def = new Integration_Definition__c(
            Name = name,
            Migration_Id__c = Util_System.generateGUID(),
            Error_Handling__c = 'StopOnError', // Easier debugging
            CurrencyIsoCode = 'EUR'
        );
        return def;
    }

    public static Integration_Event__c createIntegrationEvent(String parentGUID, Integer executionOrder, Logger2.LOGGING_TYPE loggingType, String name, String type, String handlerName) {
        Integration_Event__c event = new Integration_Event__c(
            Integration_Definition__r = new Integration_Definition__c(Migration_Id__c = parentGUID),
            Name = name,
            Execution_Order__c = executionOrder,
            Logging_Type__c = loggingType.name(),
            Type__c = type,
            Handler_Name__c = handlerName,
            Is_Active__c = true,
            CurrencyIsoCode = 'EUR',
            Migration_Id__c = Util_System.generateGUID()
        );
        return event;
    }

    public static Event_Field__c createEventField(String parentGUID, String name, String mapping, String dataType, String io) {
        Event_Field__c field = new Event_Field__c(
            Integration_Event__r = new Integration_Event__c(Migration_Id__c = parentGUID),
            Name = name,
            Mapping_Name__c = mapping,
            Data_Type__c = dataType,
            Type__c = io,
            Is_Active__c = true,
            CurrencyIsoCode = 'EUR',
            Migration_Id__c = Util_System.generateGUID()
        );
        return field;
    }

    public static Event_Field__c createStaticEventField(String parentGUID, String name, String mapping, String dataType, String value) {
        Event_Field__c field = Test_DataIntegrationDefinition.createEventField(parentGUID, name, mapping, dataType, 'Input');
        field.Static_Value__c = value;
        return field;
    }
}