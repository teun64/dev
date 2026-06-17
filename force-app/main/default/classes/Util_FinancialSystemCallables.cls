public with sharing class Util_FinancialSystemCallables {
  public class AccountSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      System.debug('AccountSync ' + inputParams.get('AccountSync'));
      if (inputParams.get('AccountSync') != true) {
        return inputParams;
      }
      // Account validation
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Boolean skipDataCheck = FeatureManagement.checkPermission(
        'cp_miIntegrationSkipDataCheck'
      );
      if (!skipDataCheck) {
        if (
          acc.Reseller_Name__c == '1' &&
          acc.RecordTypeId !=
          Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('B2C')
            .getRecordTypeId() &&
          acc.ShippingCountryCode == 'NL' &&
          acc.Block_Syncing_Exact__c
        ) {
          throw new Util_System.CustomException(
            'This account is not validated by Web Services, this validation has to be completed before this account can be synchronised.'
          );
        } else if (
          Util_System.requireBankDetails.contains(
            acc.Payment_Method_Contracts__c
          ) &&
          (String.isBlank(acc.Bank_Account_Number__c) ||
          String.isBlank(acc.Bank_Account__c))
        ) {
          //Reseller 1 requires an bank account
          throw new Util_System.CustomException(
            'This account can not be synchronised because the bank account is not filled in.'
          );
        } else if (
          String.isBlank(acc.ShippingCountryCode) ||
          String.isBlank(acc.ShippingStreet) ||
          String.isBlank(acc.ShippingPostalCode) ||
          String.isBlank(acc.ShippingCity)
        ) {
          throw new Util_System.CustomException(
            'This account can not be synchronised because the shipping address is not filled in.'
          );
        } else if (
          String.isBlank(acc.BillingCountryCode) ||
          String.isBlank(acc.BillingStreet) ||
          String.isBlank(acc.BillingPostalCode) ||
          String.isBlank(acc.BillingCity)
        ) {
          throw new Util_System.CustomException(
            'This account can not be synchronised because the billing address is not filled in.'
          );
        }
      }

      // Sync account
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
      String method = Util_FinancialSystem.syncAccount(acc, admin, logGuid);

      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class ContactPersonSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      System.debug(inputParams);
      System.debug(inputParams.get('syncContact'));
      System.debug(inputParams.get('syncContact') instanceof Boolean);
      System.debug(inputParams.get('contactPerson'));
      if (inputParams.get('syncContact') != true) {
        System.debug('skipping');
        return inputParams;
      }
      // Validate relation set
      AccountContactRelation relation = (AccountContactRelation) inputParams.get(
        'contactPerson'
      );
      if (relation == null) {
        System.debug('throwing');
        throw new Util_System.CustomException(
          'Could not find contact relation to sync, when trying to sync contact'
        );
      }
      System.debug('querying');
      // Query account if it's not set
      if (
        inputParams.get('accountRecord') == null &&
        inputParams.get('contactPerson') != null
      ) {
        Id accId = ((AccountContactRelation) inputParams.get('contactPerson'))
          .AccountId;
        inputParams.put(
          'accountRecord',
          [
              SELECT Id, FinancialIdAccount__c, Reseller_Name__c
              FROM Account
              WHERE Id = :accId
            ]
            .get(0)
        );
      }
      System.debug('queried');

      // Get integration required data
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      // Sync contact person
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Contact con = [
        SELECT Id, FirstName, MiddleName, LastName, Email, Phone
        FROM Contact
        WHERE Id = :relation.ContactId
      ];
      System.debug('do sync');
      Util_FinancialSystem.syncContact(acc, con, relation, admin, logGuid);
      inputParams.put('saveContactPerson', true);

      return inputParams;
    }
  }

  public class ShippingAddressSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      if (inputParams.get('syncShippingAddress') != true) {
        return inputParams;
      }
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.syncShippingAddress(acc, admin, logGuid);
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class BillingAddressSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      if (inputParams.get('syncBillingAddress') != true) {
        return inputParams;
      }
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.syncBillingAddress(acc, admin, logGuid);
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class VisitingAddressSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      if (inputParams.get('syncVisitingAddress') != true) {
        return inputParams;
      }
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.syncVisitingAddress(acc, admin, logGuid);
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class BankAccountSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      if (inputParams.get('syncBankAccount') != true) {
        return inputParams;
      }
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      Util_FinancialSystem.getLimits(admin).reserveCapacity(3);
      Util_FinancialSystem.syncBankAccount(acc, admin, logGuid);
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class MandateSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      if (inputParams.get('syncMandate') != true) {
        return inputParams;
      }
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.syncMandate(acc, admin, logGuid);
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class GetDebtorNumber implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      if (!String.isBlank(acc.FinancialDebtorNumber__c)) {
        return inputParams;
      }
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);

      // Get Debtor number from Financial
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      acc.FinancialDebtorNumber__c = Util_FinancialSystem.getDebtorNumber(
        acc,
        admin,
        logGuid
      );
      // Store on Account
      Subscription25__Debtor_Number__c debtorNumber = Util_Rest.createDebtorNumber(
        acc,
        admin
      );
      // Store for Subscription
      Database.upsert(
        debtorNumber,
        Subscription25__Debtor_Number__c.Subscription25__Composite_Key__c
      );
      inputParams.put('saveAccount', true);
      return inputParams;
    }
  }

  public class GetProductIdsFinancialSystem implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      Order ord = Util_FinancialSystemCallables.getOrder(inputParams);

      // Identify items that require syncing
      Set<String> codes = new Set<String>();
      List<Subscription25__Administration_Product__c> adminProds2Update = new List<Subscription25__Administration_Product__c>();
      for (
        Subscription25__Administration_Product__c adminProd : Util_FinancialSystemCallables.getAdminProductsForOrder(
          inputParams
        )
      ) {
        if (String.isBlank(adminProd.Exact_Id__c)) {
          codes.add(adminProd.Subscription25__Product__r.ProductCode);
          adminProds2Update.add(adminProd);
        }
      }

      // Sync and match product Ids (if necessary)
      if (!codes.isEmpty()) {
        Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
          inputParams
        );
        Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
        String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
        Map<String, String> financialItemIds2Add = Util_FinancialSystem.getFinancialItemIds(
          admin,
          codes,
          logGuid
        );
        for (
          Subscription25__Administration_Product__c adminProd : adminProds2Update
        ) {
          if (
            financialItemIds2Add.containsKey(
              adminProd.Subscription25__Product__r.ProductCode
            )
          ) {
            adminProd.Exact_Id__c = financialItemIds2Add.get(
              adminProd.Subscription25__Product__r.ProductCode
            );
          }
        }
      }
      inputParams.put('saveAdminProducts', true);

      // Validate all ids synced
      for (
        Subscription25__Administration_Product__c adminProd : adminProds2Update
      ) {
        if (String.isBlank(adminProd.Exact_ID__c)) {
          throw new Util_System.CustomException(
            'Some of the order items are not available in financial'
          );
        }
      }

      return inputParams;
    }
  }

  public class OrderSync implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      system.debug('OrderSync -> Start');
      if (inputParams.get('syncOrder') != true) {
        system.debug('OrderSync -> Oeps' + inputParams);
        return inputParams;
      }
      system.debug('OrderSync -> Param Check Passed');

      // Get data
      Order ord = Util_FinancialSystemCallables.getOrder(inputParams);
      system.debug('OrderSync -> ' + ord);
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      system.debug('OrderSync -> ' + acc);
      system.debug('OrderSync -> ' + inputParams.get('contactPerson'));
      AccountContactRelation acr = Util_FinancialSystemCallables.getContactRelation(
        inputParams
      );
      system.debug('OrderSync -> ' + acr);
      // Validate data
      if (!String.isBlank(ord.Exact_Id__c)) {
        throw new Util_System.CustomException(
          'This order was already synchronised'
        );
      }
      if (String.isBlank(acc.FinancialIdAccount__c) && !test.isRunningTest()) {
        throw new Util_System.CustomException(
          'The account has an invalid debtor number in Financial or is not synced yet'
        );
      }
      system.debug(acr);
      if (String.isBlank(acr?.FinancialIdContact__c)) {
        throw new Util_System.CustomException(
          'This account does not have a billing contact assigned'
        );
      }

      system.debug('OrderSync -> Record validation passed');

      // Ensure payment method is filled
      if (
        (String.isBlank(ord.Payment_Method__c)) ||
        ((String.isNotBlank(ord.Payment_Method__c)) &&
        (ord.Payment_Method__c.left(1) == 'I') &&
        (String.isBlank(acc.Bank_Account_Number__c)))
      ) {
        ord.Payment_Method__c = '08';
      }

      // Map Financial item ids
      Map<String, String> financialItemIds = new Map<String, String>();
      for (
        Subscription25__Administration_Product__c adminProduct : Util_FinancialSystemCallables.getAdminProductsForOrder(
          inputParams
        )
      ) {
        system.debug('OrderSync -> ' + adminProduct.Exact_Id__c);
        financialItemIds.put(
          adminProduct.Subscription25__Product__r.ProductCode,
          adminProduct.Exact_Id__c
        );
      }

      // Get Opportunity
      List<Opportunity> opps = [
        SELECT
          Id,
          Name,
          Customer_Reference__c,
          Installation_Notes__c,
          Sales_Contact__c,
          Sales_Contact__r.Name,
          Sales_Contact__r.Email,
          Sales_Contact__r.Phone
        FROM Opportunity
        WHERE Id = :ord.OpportunityId
      ];
      if (opps.isEmpty()) {
        throw new Util_System.CustomException(
          'This order does not have an opportunity assigned'
        );
      }
      Opportunity opp = opps.get(0);

      // Create order in Financial
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      system.debug('OrderSync -> Administation passed');
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      system.debug('OrderSync -> reserveCapacity passed');
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
      system.debug('OrderSync -> getLogGUID passed');
      List<OrderItem> ordItems = Util_FinancialSystemCallables.getItemsForOrder(
        inputParams
      );
      system.debug('OrderSync -> getItemsForOrder passed');
      Util_FinancialSystem.FinancialOrder financialOrd = new Util_FinancialSystem.FinancialOrder(
        ord,
        opp,
        ordItems,
        financialItemIds,
        acc,
        acr,
        admin
      );
      system.debug('OrderSync -> financialOrd passed');
      String endpoint = String.format(
        Util_FinancialSystem.ORDER_ENDPOINT,
        new List<String>{ admin.Subscription25__Twinfield_Company_Code__c }
      );
      system.debug('OrderSync -> endpoint passed');
      String response = Util_FinancialSystem.doRequest(
        admin,
        endpoint,
        null,
        'POST',
        JSON.serialize(financialOrd),
        logGuid
      );
      system.debug('OrderSync -> doRequest passed' + response);
      Util_FinancialSystem.FinancialOrder responseOrder = (Util_FinancialSystem.FinancialOrder) JSON.deserialize(
        response,
        Util_FinancialSystem.FinancialOrder.class
      );
      system.debug('OrderSync -> responseOrder passed' + responseOrder);
      ord.Exact_Id__c = responseOrder.getOrderId();
      ord.Exact_Order_Number__c = responseOrder.getOrderNumber();

      // Sync account
      // check statement below
      // String method = Util_FinancialSystem.syncAccount(acc, admin, logGuid);

      inputParams.put('saveOrder', true);
      system.debug(
        'OrderSync -> saveOrder passed' + inputParams.get('saveOrder')
      );
      return inputParams;
    }
  }

  public class GetSalesOrderLines implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      // Get synced Order Lines for the Ids
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      Order ord = Util_FinancialSystemCallables.getOrder(inputParams);
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.FinancialOrderLines orderLines = Util_FinancialSystem.getSalesOrderLines(
        admin,
        ord.Exact_Id__c,
        logGuid
      );
      System.debug(orderLines);
      // Map found Order Lines by financial Item Id
      Map<String, Util_FinancialSystem.FinancialOrderLine> linesByItemId = new Map<String, Util_FinancialSystem.FinancialOrderLine>();
      for (
        Util_FinancialSystem.FinancialOrderLine line : orderLines.getResults()
      ) {
        linesByItemId.put(line.getItemId(), line);
      }
      System.debug(linesByItemId);

      // Map Financial item ids to product code
      Map<String, String> financialItemIds = new Map<String, String>();
      for (
        Subscription25__Administration_Product__c adminProduct : Util_FinancialSystemCallables.getAdminProductsForOrder(
          inputParams
        )
      ) {
        financialItemIds.put(
          adminProduct.Subscription25__Product__r.ProductCode,
          adminProduct.Exact_Id__c
        );
      }
      System.debug(financialItemIds);

      // Match and set order line ids
      for (
        OrderItem oi : Util_FinancialSystemCallables.getItemsForOrder(
          inputParams
        )
      ) {
        String itemId = financialItemIds.get(oi.Product2.ProductCode);
        Util_FinancialSystem.FinancialOrderLine line = linesByItemId.get(
          itemId
        );
        oi.FinancialId__c = line?.getId();
        inputParams.put('saveOrderItems', true);
      }

      // Do the same for Contract Products
      for (
        Subscription25__Contract_Product__c contractProduct : Util_FinancialSystemCallables.getContractProductsForOrder(
          inputParams
        )
      ) {
        System.debug(contractProduct);
        contractProduct.FinancialIdProduct__c = financialItemIds.get(
          contractProduct.Subscription25__Product__r.ProductCode
        );
        inputParams.put('saveContractProducts', true);
      }

      return inputParams;
    }
  }

  public class FinalizeInvoice implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      System.debug('Fin');
      System.debug(inputParams.get('finalizeInvoice'));
      if (inputParams.get('finalizeInvoice') != true) {
        return inputParams;
      }
      Subscription25__Invoice__c invoice = Util_FinancialSystemCallables.getInvoice(
        inputParams
      );
      String templateId = Util_FinancialSystem.getFinancialInvoiceTemplateId(
        invoice.Reseller__c,
        invoice.Payment_Method_Result__c,
        invoice.Subscription25__Total_Amount__c
      );

      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Util_FinancialSystem.finalizeInvoice(
        admin,
        invoice.FinancialId__c,
        invoice.Subscription25__Invoice_Date__c,
        templateId,
        admin.Subscription25__Twinfield_Company_Code__c,
        logGuid
      );
      invoice.Invoice_Printed_In_Exact__c = true;
      inputParams.put('saveInvoice', true);

      return inputParams;
    }
  }

  public class GetInvoiceDetails implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      // if (inputParams.get('getInvoiceDetails') != true) {
      //     return inputParams;
      // }
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      String logGuid = Util_FinancialSystemCallables.getLogGUID(inputParams);
      Subscription25__Invoice__c invoice = Util_FinancialSystemCallables.getInvoice(
        inputParams
      );

      Util_FinancialSystem.getLimits(admin).reserveCapacity(1);
      Map<String, String> invoiceDetails = Util_FinancialSystem.getInvoiceDetails(
        admin,
        invoice.Subscription25__Exact_Order_Number__c,
        admin.Subscription25__Twinfield_Company_Code__c,
        logGuid
      );

      if (invoiceDetails.get('Status') != '50') {
        invoice.Invoice_Printed_In_Exact__c = false;
      }
      if (!String.isBlank((String) invoiceDetails.get('InvoiceNumber'))) {
        invoice.Subscription25__Invoice_Number__c =
          admin.Subscription25__Invoice_Number_Prefix__c +
          invoiceDetails.get('InvoiceNumber');
      }
      if (!String.isBlank((String) invoiceDetails.get('InvoiceID'))) {
        invoice.FinancialId__c = invoiceDetails.get('InvoiceID');
      }
      inputParams.put('saveInvoice', true);

      return inputParams;
    }
  }

  public class UpsertRecord implements Callable {
    public Object call(String action, Map<String, Object> inputParams) {
      SObject rec = (SObject) inputParams.get('record');
      if (rec != null) {
        Database.upsert(rec);
      }
      return inputParams;
    }
  }

  private static Subscription25__Administration__c getAdministration(
    Map<String, Object> inputParams
  ) {
    Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
    Integer adminExternalId = Util_System.getAdminExternalId(
      Long.valueOf(acc?.Reseller_Name__c ?? '1')
    );
    Subscription25__Administration__c admin = Util_System.getAdministration(
      adminExternalId
    );

    if (
      admin?.Subscription25__Synchronisation__c != 'Financial' ||
      !admin.Subscription25__Active__c
    ) {
      throw new Util_System.CustomException(
        'This accounts reseller does not synchronize with Financial'
      );
    }
    return admin;
  }

  private static String getLogGUID(Map<String, Object> inputParams) {
    String logGuid = (String) inputParams.get('logguid');
    return logGuid;
  }

  private static Account getAccount(Map<String, Object> inputParams) {
    Account acc = (Account) inputParams.get('accountRecord');
    if (acc == null) {
      Id accountId;
      if (inputParams.get('orderRecord') != null) {
        accountId = Util_FinancialSystemCallables.getOrder(inputParams)
          .AccountId;
      }

      if (accountId != null) {
        acc = [
          SELECT
            Id,
            FinancialIdAccount__c,
            Reseller_Name__c,
            Bank_Account_Number__c,
            Contact_person__c
          FROM Account
          WHERE Id = :accountId
        ];
        inputParams.put('accountRecord', acc);
        inputParams.put('accountRecordLoaded', true);
      }
    }
    return acc;
  }

  private static Order getOrder(Map<String, Object> inputParams) {
    Order ord = (Order) inputParams.get('orderRecord');
    if (
      ord != null &&
      ord.Id != null &&
      inputParams.get('orderRecordLoaded') != true
    ) {
      ord = [
        SELECT
          Id,
          AccountId,
          OpportunityId,
          Contract__c,
          Exact_Id__c,
          Exact_Order_Number__c,
          Payment_Method__c,
          Payment_Method_Result__c,
          Payment_Reference__c,
          Reseller__c,
          Sales_Channel__c
        FROM Order
        WHERE Id = :ord.Id
      ];
      inputParams.put('orderRecord', ord);
      inputParams.put('orderRecordLoaded', true);
    }
    return ord;
  }

  private static List<OrderItem> getItemsForOrder(
    Map<String, Object> inputParams
  ) {
    if (!inputParams.containsKey('orderItems')) {
      inputParams.put(
        'orderItems',
        [
          SELECT
            Id,
            Quantity,
            UnitPrice,
            Product_Name__c,
            Product_Code_Customer__c,
            Partner_Code__c,
            Product2Id,
            Product2.ProductCode,
            Product2.Name,
            Product2.Generate_Partner_Code__c,
            Product2.RecordType.DeveloperName
          FROM OrderItem
          WHERE
            OrderId = :Util_FinancialSystemCallables.getOrder(inputParams).Id
        ]
      );
    }
    List<OrderItem> orderItems = (List<OrderItem>) inputParams.get(
      'orderItems'
    );
    return orderItems;
  }

  private static List<Subscription25__Administration_Product__c> getAdminProductsForOrder(
    Map<String, Object> inputParams
  ) {
    if (!inputParams.containsKey('adminProducts')) {
      Subscription25__Administration__c admin = Util_FinancialSystemCallables.getAdministration(
        inputParams
      );
      List<OrderItem> ordItems = Util_FinancialSystemCallables.getItemsForOrder(
        inputParams
      );
      Set<Id> productIds = Util_System.collectIdValues(
        ordItems,
        'Product2Id',
        false
      );

      inputParams.put(
        'adminProducts',
        [
          SELECT
            Id,
            Subscription25__Product__c,
            Subscription25__Product__r.ProductCode,
            Exact_Id__c
          FROM Subscription25__Administration_Product__c
          WHERE
            Subscription25__Administration__c = :admin.Id
            AND Subscription25__Product__c IN :productIds
          LIMIT 10000
        ]
      );
    }
    List<Subscription25__Administration_Product__c> adminProducts = (List<Subscription25__Administration_Product__c>) inputParams.get(
      'adminProducts'
    );
    return adminProducts;
  }

  private static List<Subscription25__Contract_Product__c> getContractProductsForOrder(
    Map<String, Object> inputParams
  ) {
    System.debug(inputParams.containsKey('contractProducts'));
    if (!inputParams.containsKey('contractProducts')) {
      Order ord = Util_FinancialSystemCallables.getOrder(inputParams);
      List<OrderItem> ordItems = Util_FinancialSystemCallables.getItemsForOrder(
        inputParams
      );
      System.debug(ordItems);
      Set<Id> productIds = Util_System.collectIdValues(
        ordItems,
        'Product2Id',
        false
      );
      System.debug(productIds);
      System.debug(ord.Contract__c);
      System.debug(
        [
          SELECT
            Id,
            Subscription25__Contract__c,
            Subscription25__Product__c,
            FinancialIdProduct__c
          FROM Subscription25__Contract_Product__c
        ]
      );

      inputParams.put(
        'contractProducts',
        [
          SELECT Id, Subscription25__Product__r.ProductCode
          FROM Subscription25__Contract_Product__c
          WHERE
            Subscription25__Contract__c = :ord.Contract__c
            AND Subscription25__Product__c IN :productIds
        ]
      );
    }
    List<Subscription25__Contract_Product__c> contractProducts = (List<Subscription25__Contract_Product__c>) inputParams.get(
      'contractProducts'
    );
    return contractProducts;
  }

  private static AccountContactRelation getContactRelation(
    Map<String, Object> inputParams
  ) {
    AccountContactRelation rel = (AccountContactRelation) inputParams.get(
      'contactPerson'
    );
    if (rel == null) {
      Account acc = Util_FinancialSystemCallables.getAccount(inputParams);
      Id contactId;
      try {
        contactId = acc?.Contact_person__c;
      } catch (SObjectException e) {
        acc = [
          SELECT
            Id,
            FinancialIdAccount__c,
            Reseller_Name__c,
            Bank_Account_Number__c,
            Contact_person__c
          FROM Account
          WHERE Id = :acc.Id
        ];
        inputParams.put('accountRecord', acc);
        inputParams.put('accountRecordLoaded', true);
        contactId = acc.Contact_person__c;
      }

      if (contactId == null) {
        return null;
      }

      List<AccountContactRelation> relations = [
        SELECT
          Id,
          AccountId,
          ContactId,
          FinancialIdContact__c,
          Contact.FirstName,
          Contact.MiddleName,
          Contact.LastName,
          Contact.Email,
          Contact.Phone
        FROM AccountContactRelation
        WHERE
          AccountId = :acc.Id
          AND ContactId = :contactId
          AND Roles INCLUDES ('Billing')
        LIMIT 1
      ];
      if (!relations.isEmpty()) {
        rel = relations[0];
        inputParams.put('contactPerson', rel);
      }
    }
    return rel;
  }

  private static Subscription25__Invoice__c getInvoice(
    Map<String, Object> inputParams
  ) {
    Subscription25__Invoice__c inv = (Subscription25__Invoice__c) inputParams.get(
      'invoice'
    );
    return inv;
  }
}
