public class Trigger_Order {
	public static void run(){
		if(!Trigger.isExecuting){
			return;
		}

		Trigger_Order.setInvoiceDate();
	}

	private static void setInvoiceDate(){
		if(!(Trigger.isBefore && Trigger.isInsert)){
			return;
		}

		List<Order> iterList = Trigger.new;
		Set<Id> acctIds = Util_System.collectIdValues(iterList, 'AccountId');
		Set<Id> recOrderIds = Util_System.collectIdValues(iterList, 'Subscription25__Recurring_Order__c');
		Map<Id, Account> acctMap = new Map<Id, Account>([
			SELECT Id, Invoice_Frequency__c, OrderOffsetTerm__c, Reseller_Name__c, Payment_Method_Contracts__c, Subscription25__Create_Invoices_As_Draft__c  FROM Account WHERE Id IN :acctIds
		]);
		Map<Id, Subscription25__Recurring_Order__c> recOrderMap = new Map<Id, Subscription25__Recurring_Order__c>([
			SELECT Id, Subscription25__Months_In_Advance__c  FROM Subscription25__Recurring_Order__c WHERE Id IN :recOrderIds
		]);
		Account curAcct;
		Subscription25__Recurring_Order__c curRecOrder;
		Date curInvDate;
		Date newInvDate;
		String paymentMethod;
		Date nextMonday;
		Integer curInvDay;
		Integer curMonthsInAdvance = 0;

		for(Order ordNew : iterList){ 

			if ((ordNew.Type == 'Opportunity') || (ordNew.Type == 'Hardware')) {
				continue;
			}

			//depending on the invoice frequency of the account, we may need to move the invoice date of the order
			curAcct = acctMap.get(ordNew.AccountId);
			if (String.isNotBlank(ordNew.Subscription25__Recurring_Order__c)) {
				curRecOrder = recOrderMap.get(ordNew.Subscription25__Recurring_Order__c);
				curMonthsInAdvance = curRecOrder.Subscription25__Months_In_Advance__c?.intValue();
			}

			curInvDate = null;
			newInvDate = null;

			// Use curMonthsInAdvance to determine the invoice date
			curInvDate = (curMonthsInAdvance == 0) ? ordNew.EffectiveDate : ordNew.EffectiveDate.addMonths((curMonthsInAdvance * -1));
			//prefent invoicedates in the past
			curInvDate = (ordNew.Subscription25__Invoice_Date__c != null) ? ordNew.Subscription25__Invoice_Date__c : ((curInvDate > date.today()) ? date.today() : curInvDate);
			curInvDate = ((ordNew.EndDate != null) && (ordNew.EndDate > curInvDate) && (ordNew.EndDate < date.today())) ? date.today() : curInvDate;

			paymentMethod = (ordNew.Payment_Method__c == null) ? curAcct.Payment_Method_Contracts__c : ordNew.Payment_Method__c;

			//20240315 - TRi - orders paid by card or payment provider are processed on the next invoice cycle
			if ((paymentMethod == null) || (paymentMethod.left(1) == 'p')) {
				continue;
			}

			//20221101 - TRi - if the reseller_name__c = 6 and the payment method is I0 it overrides the Invoice Frequency
			// invoice date moved to the 9 of the (next) month
			if((curAcct.Reseller_name__c == '6') && (paymentMethod == 'I0')) {
				// invoices are generated at 20:00  -> only for the orders generate and starting on the 9th of the month
				newInvDate = ((curInvDate.day() >= 9) || ((curInvDate == date.today()) && (date.today().day() == 8) && (datetime.now().hourGmt() >= 18))) ? curInvDate.addMonths(1).toStartOfMonth().addDays(7) : curInvDate.toStartOfMonth().addDays(7);
				ordNew.Subscription25__Invoice_Date__c = newInvDate;
				continue;
			}

			//if the field is not set or set to daily we don't have to do anything
			if(String.isBlank(curAcct.Invoice_Frequency__c) || curAcct.Invoice_Frequency__c == 'Daily'){
				continue;
			}

			if(curAcct.Invoice_Frequency__c == 'First of the month'){
				//set the invoice date to the first of the next month, if it's after the first of the current one
				newInvDate = curInvDate.day() != 1 ? curInvDate.addMonths(1).toStartOfMonth() : curInvdate;
			} else if(curAcct.Invoice_Frequency__c == 'Last of the month'){
				//set the invoice date to the last day of this month
				newInvDate = curInvDate.addDays(1).day() != 1 ? curInvDate.addMonths(1).toStartOfMonth().addDays(-1) : curInvdate;
			} else if(curAcct.Invoice_Frequency__c == 'First & last of the month'){
				//set the invoice date to the last day of this month, unless it's currently on the first
				newInvDate = curInvDate;
				if(newInvDate.day() != 1){
					newInvDate = curInvDate.addDays(1).day() != 1 ? curInvDate.addMonths(1).toStartOfMonth().addDays(-1) : curInvdate;
				}
			} else if(curAcct.Invoice_Frequency__c == 'Weekly'){
				//set the invoice date to the next monday (if the current date is monday move it to next monday as well)
				// date 1900-01-01 is a monday, other valid years, 1990, 2001
				curInvDay = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(curInvDate), 7); //this is 0 if curInvDate = monday
				//get the first monday after the current invoice date
				nextMonday = curInvDate.addDays(7 - curInvDay);
				newInvDate = nextMonday;
			}

			//system.debug('curInvDate = ' + curInvDate);
			//system.debug('newInvDate = ' + newInvDate);
			ordNew.Subscription25__Invoice_Date__c = newInvDate;
			
		}
	}
}