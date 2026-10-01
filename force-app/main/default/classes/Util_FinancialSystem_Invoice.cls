/**
 * Invoice finalisation in the financial system (Exact Online), moved from Util_Exact.
 * Used by Batch_FinalizeInvoices / Batch_FinalizeInvoicesLimited (one invoice per execute).
 * Note: in production the Subscription25 package job Job_FinalizeInvoicesInExact finalises invoices too.
 */
public without sharing class Util_FinancialSystem_Invoice {
	private static final String SALES_INVOICE_GET_ENDPOINT = 'api/v1/{0}/bulk/salesinvoice/SalesInvoices';
	private static final String SALES_INVOICE_PRINT_ENDPOINT = 'api/v1/{0}/salesinvoice/PrintedSalesInvoices';

	public static List<String> finalizeInvoice(Id invoiceId) {
		return Util_FinancialSystem_Invoice.finalizeInvoice(invoiceId, null);
	}

	/**
	 * Prints (finalises) the invoice in Exact and stores the Exact invoice number on it.
	 * @return error messages; empty when successful
	 */
	public static List<String> finalizeInvoice(Id invoiceId, String logGUID) {
		Subscription25__Invoice__c inv = Util_FinancialSystem_Invoice.getInvoice(invoiceId);

		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Invoice', 'finalize2Exact', invoiceId, inv.Name, '');
		List<String> msgs = new List<String>();
		Subscription25__Administration__c admin = inv.Subscription25__Administration__r;
		try {
			if (String.isBlank(inv.Subscription25__Exact_Order_Number__c)) {
				throw new Util_System.CustomException('This invoice is not yet synced');
			}
			if (!String.isBlank(inv.Subscription25__Invoice_Number__c)) {
				throw new Util_System.CustomException('This invoice is already finalized');
			}

			//first of all, we need to get the GUID of the invoice, we can get that based on the order number
			Map<String, String> invoiceDetails = Util_FinancialSystem_Invoice.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, mainLog.GUID__c);

			//if the invoice already has an invoice number, store it on the invoice, and we're done
			if (!String.isBlank(invoiceDetails.get('InvoiceNumber'))) {
				inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
			} else {
				String templateId = Util_FinancialSystem_Invoice.getExactInvoiceTemplateId(inv.Reseller__c, inv.Payment_Method_Result__c, inv.Subscription25__Total_Amount__c);
				Util_FinancialSystem_Invoice.printInvoice(admin, invoiceDetails.get('InvoiceID'), inv.Subscription25__Invoice_Date__c, templateId, mainLog.GUID__c);
				inv.Subscription25__Finalized_In_Exact__c = true;

				//now we can get the invoice details again to get the invoice number
				try {
					invoiceDetails = Util_FinancialSystem_Invoice.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, mainLog.GUID__c);
					String invoiceNumber = String.isBlank(invoiceDetails.get('InvoiceNumber')) ? '' : invoiceDetails.get('InvoiceNumber');
					invoiceNumber = (invoiceNumber == 'null') ? '' : invoiceNumber;
					if (String.isNotBlank(invoiceNumber)) {
						inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceNumber;
					}
				} catch (Exception e) {
					//if loading the invoice number fails, leave it; next time the job runs it reloads the invoice number
				}
			}
			Util_FinancialSystem_Invoice.updateInvoice(inv);
		} catch (Util_System.FinancialSyncException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add(e.getMessage());
		} catch (Util_FinancialSystem.RateLimitException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n';
			msgs.add(e.getMessage());
		} catch (Util_System.CustomException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add(e.getMessage());
		} catch (Exception e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
			mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add('Unhandled exception occurred.');
		}

		Util_FinancialSystem.saveLogs(new List<Event_Log__c>{ mainLog }, new Set<String>{ admin?.Subscription25__Named_Credential__c }, mainLog.GUID__c);
		return msgs;
	}

	public static List<String> loadInvoiceNumber(Id invoiceId) {
		return Util_FinancialSystem_Invoice.loadInvoiceNumber(invoiceId, null);
	}

	/**
	 * For an invoice that was already printed in Exact but has no invoice number yet: load the number.
	 * @return error messages; empty when successful
	 */
	public static List<String> loadInvoiceNumber(Id invoiceId, String logGUID) {
		Subscription25__Invoice__c inv = Util_FinancialSystem_Invoice.getInvoice(invoiceId);
		Event_Log__c mainLog = Util_Event.getLog(logGUID, 'S', 'E', 'Invoice', 'loadInvoiceNumber', invoiceId, inv.Name, null);
		List<String> msgs = new List<String>();
		Subscription25__Administration__c admin = inv.Subscription25__Administration__r;
		try {
			if (!inv.Subscription25__Finalized_In_Exact__c) {
				throw new Util_System.CustomException('This invoice is not yet synced');
			}
			if (!String.isBlank(inv.Subscription25__Invoice_Number__c)) {
				throw new Util_System.CustomException('This invoice is already finalized');
			}

			Map<String, String> invoiceDetails = Util_FinancialSystem_Invoice.getInvoiceDetails(admin, inv.Subscription25__Exact_Order_Number__c, mainLog.GUID__c);
			//if the invoice status from exact is not 50, the actual printing failed, so disable that checkbox
			if (invoiceDetails.get('Status') != '50') {
				inv.Subscription25__Finalized_In_Exact__c = false;
			} else {
				inv.Subscription25__Invoice_Number__c = admin.Subscription25__Invoice_Number_Prefix__c + invoiceDetails.get('InvoiceNumber');
			}
			Util_FinancialSystem_Invoice.updateInvoice(inv);
		} catch (Util_System.FinancialSyncException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add(e.getMessage());
		} catch (Util_FinancialSystem.RateLimitException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c += e.getMessage() + '\n';
			msgs.add(e.getMessage());
		} catch (Util_System.CustomException e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.ERROR.name();
			mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add(e.getMessage());
		} catch (Exception e) {
			mainlog.Result_Status__c = Util_Event.LogResultStatus.UNHANDLED_EXCEPTION.name();
			mainlog.Message__c = e.getMessage() + '\n' + e.getStackTraceString() + '\n';
			msgs.add('Unhandled exception occurred.');
		}

		Util_FinancialSystem.saveLogs(new List<Event_Log__c>{ mainLog }, new Set<String>{ admin?.Subscription25__Named_Credential__c }, mainLog.GUID__c);
		return msgs;
	}

	private static Subscription25__Invoice__c getInvoice(Id invoiceId) {
		return [
			SELECT Id, Name, Subscription25__Exact_Order_Number__c, Subscription25__Invoice_Number__c,
				Subscription25__Invoice_Date__c, Payment_Method__c, Payment_Method_Result__c, Subscription25__Total_Amount__c,
				Subscription25__Finalized_In_Exact__c, Reseller__c, Sales_Channel__c,
				Subscription25__Administration__c,
				Subscription25__Administration__r.Id,
				Subscription25__Administration__r.Name,
				Subscription25__Administration__r.Daily_Limit__c,
				Subscription25__Administration__r.FinancialRateLimitMaxPercentage__c,
				Subscription25__Administration__r.FinancialRateLimitRemaining__c,
				Subscription25__Administration__r.FinancialRateLimitResetOn__c,
				Subscription25__Administration__r.Acceptance_Environment_Available__c,
				Subscription25__Administration__r.Subscription25__Named_Credential__c,
				Subscription25__Administration__r.Subscription25__Twinfield_Company_Code__c,
				Subscription25__Administration__r.Subscription25__Invoice_Number_Prefix__c
			FROM Subscription25__Invoice__c
			WHERE Id = :invoiceId
			WITH SYSTEM_MODE
		];
	}

	private static void updateInvoice(Subscription25__Invoice__c inv) {
		Boolean curEru = Util_System.getEruIluvatar();
		if (!curEru) {
			Util_System.setEruIluvatar(true);
		}
		Database.update(inv, AccessLevel.SYSTEM_MODE);
		if (!curEru) {
			Util_System.setEruIluvatar(false);
		}
	}

	@TestVisible
	private static String getExactInvoiceTemplateId(String reseller, String paymentMethod, Decimal amount) {
		String templateId = '';
		String paymentCondition = (amount < 0) ? 'cr' : paymentMethod;
		if (String.isNotBlank(reseller) && String.isNotBlank(paymentCondition)) {
			List<Payment_Setting__mdt> settings = [
				SELECT Exact_Invoice_Template__c FROM Payment_Setting__mdt
				WHERE Reseller__c = :reseller AND Method__c = :paymentCondition
				LIMIT 1
			];
			// as in Util_Exact: without a layout setting the invoice is not printed
			if (settings.isEmpty()) {
				throw new Util_System.CustomException('No Payment_Setting__mdt invoice layout for reseller ' + reseller + ' and payment condition ' + paymentCondition);
			}
			templateId = settings[0].Exact_Invoice_Template__c;
		}
		return templateId;
	}

	private static Map<String, String> getInvoiceDetails(Subscription25__Administration__c admin, String orderNumber, String logGuid) {
		Map<String, String> params = new Map<String, String>();
		params.put('$select', 'InvoiceID,InvoiceNumber,Status');
		params.put('$filter', 'OrderNumber eq ' + orderNumber);
		String endpoint = String.format(Util_FinancialSystem_Invoice.SALES_INVOICE_GET_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
		String response = Util_FinancialSystem.doRequest(admin, endpoint, params, 'GET', null, logGuid);

		Util_FinancialSystem_Invoice.ExactInvoices allInvoices = (Util_FinancialSystem_Invoice.ExactInvoices) JSON.deserialize(response, Util_FinancialSystem_Invoice.ExactInvoices.class);
		if (allInvoices == null || allInvoices.results == null || allInvoices.results.isEmpty()) {
			throw new Util_System.FinancialSyncException('No invoice found in the financial system for order number ' + orderNumber);
		}
		Map<String, String> details = new Map<String, String>();
		details.put('InvoiceID', allInvoices.results[0].InvoiceID);
		details.put('InvoiceNumber', allInvoices.results[0].InvoiceNumber);
		details.put('Status', '' + allInvoices.results[0].Status);
		return details;
	}

	private static void printInvoice(Subscription25__Administration__c admin, String invoiceId, Date invDate, String templateId, String logGuid) {
		Map<String, Object> reqMap = new Map<String, Object>();
		reqMap.put('InvoiceID', invoiceId);
		reqMap.put('InvoiceDate', Util_System.formatDate(invDate, 'yyyy-MM-dd'));
		if (!String.isBlank(templateId)) {
			reqMap.put('DocumentLayout', templateId);
		}
		reqMap.put('SendEmailToCustomer', false);
		reqMap.put('SendInvoiceToCustomerPostbox', false);
		reqMap.put('SendOutputBasedOnAccount', false);

		String endpoint = String.format(Util_FinancialSystem_Invoice.SALES_INVOICE_PRINT_ENDPOINT, new List<String>{ admin.Subscription25__Twinfield_Company_Code__c });
		Util_FinancialSystem.doRequest(admin, endpoint, null, 'POST', JSON.serialize(reqMap), logGuid);
	}

	private class ExactInvoices {
		private List<Util_FinancialSystem_Invoice.ExactInvoice> results;
	}

	private class ExactInvoice {
		private String InvoiceID;
		private String InvoiceNumber;
		private Integer Status;
	}
}
