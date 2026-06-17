@RestResource(urlMapping='/Contract')
global without sharing class Rest_Contract {

	@HttpGet
	//global static CorrectionResponse handleAction() {
    global static Util_Rest.AbstractRestResult handleAction() {
        Logger logger = Logger.getInstance();
        String sessionId = logger.startSession(RestContext.request, null, 'Salesforce');

		//result is needed for returning a custom object to the sender
		//this object is used by MI to determine which records have been added successfully to SF.
		CorrectionResponse result = new CorrectionResponse();

		try {
			Util_Rest.isRestEntry = true;
			String entityId = RestContext.request.params.get('entity');
			//String entity = RestContext.request.params.get('contractproduct');
			String platformId = RestContext.request.params.get('platform');

            entityId = (entityId == null) ? '0' : entityId.trim();
            platformId = (platformId == null) ? '0' : platformId.trim();
            logger.setSessionRecordExternalId(sessionId, entityId);
			logger.setCallingSystem(sessionId, platformId);

            String extId = ((entityId == null) ? '0' : entityId) + '-in-' + ((platformId == null) ? '0' : platformId);

			//get all contract products that are currently active for the given entity
			Map<Id, Subscription25__Contract_Product__c> cps = new Map<Id, Subscription25__Contract_Product__c>([
				SELECT Id, Subscription25__Recurring_Order__r.Subscription25__Next_Date__c
				FROM Subscription25__Contract_Product__c
				WHERE Subscription25__Status__c IN ('Ready', 'Activated', 'Closed')
					AND Subscription25__Exclude_From_Corrections__c = false
					AND Subscription25__Contract__r.Entity__r.extId__c = :extId
			]);

			// 20221118 quick fix platform bug divide price by number of recurring products part 1
			List<Subscription25__Contract_Product__c> cpr = new list<Subscription25__Contract_Product__c>([
				SELECT Id
				FROM Subscription25__Contract_Product__c
				WHERE Subscription25__Status__c IN ('Ready', 'Activated', 'Closed')
					AND Subscription25__Exclude_From_Corrections__c = false
					AND Subscription25__Contract__r.Entity__r.extId__c = :extId
					AND Subscription25__Product__r.RecordType.DeveloperName != 'Handling'
			]);

			integer cpRecurring = 1;


			//if ((cpr.size() > 0) && (Datetime.now() <= Datetime.newInstance(2023, 1, 25, 19, 0, 0) )) {
			//if ((cpr.size() > 0) && (platformId == '1')) {
			//		cpRecurring = cpr.size();
			//}

			//run the corrector for all contract products, with the correction starting a month from now
			Subscription25.Neko_Contract_0.ContractProductCorrectorInput input = new Subscription25.Neko_Contract_0.ContractProductCorrectorInput();
			input.contractProductIds = cps.keySet();
			input.createCorrectionsFrom = Date.today().addMonths(1).addDays(1);
			//input.createCorrectionsFrom = Date.today().addMonths(1);
			Subscription25.Neko_Contract_0.ContractProductCorrector corrector = new Subscription25.Neko_Contract_0.ContractProductCorrector(input);
			corrector.runCorrection();

			// 20221118 quick fix platform bug divide price by number of recurring products part 2
			decimal creditAmount;

			// 20221118 quick fix platform bug divide price by number of recurring products part 3
			//result.creditAmountNotice = corrector.output.totalCorrectionAmount;
			creditAmount = corrector.output.totalCorrectionAmount;
			creditAmount /= cpRecurring;
			creditAmount.setScale(2, RoundingMode.HALF_DOWN);
			result.creditAmountNotice = creditAmount;

			//now, do the same but with corrections from today
			input = new Subscription25.Neko_Contract_0.ContractProductCorrectorInput();
			input.contractProductIds = cps.keySet();
			input.createCorrectionsFrom = Date.today().addDays(1);
			//input.createCorrectionsFrom = Date.today();
			corrector = new Subscription25.Neko_Contract_0.ContractProductCorrector(input);
			corrector.runCorrection();

			// 20221118 quick fix platform bug divide price by number of recurring products part 4
			//result.creditAmountDirect = corrector.output.totalCorrectionAmount;
			creditAmount = corrector.output.totalCorrectionAmount;
			creditAmount /= cpRecurring;
			creditAmount.setScale(2, RoundingMode.HALF_DOWN);
			result.creditAmountDirect = creditAmount;

			//if everything went right add the following message and set Success to true.
			result.success = true;

			Util_Rest.isRestEntry = false;

		} catch (Exception e) {
			//when an error occurs: rollback the database and add the error messages to the result object, set success to false and clear the AddedRecords since none have been added.
			result.messages.add('Error: ' + e + ' ---STACK-- ' + e.getStackTraceString() + '---LINE----' + e.getLineNumber());
			result.success = false;

			Util_Rest.isRestEntry = false;
		}

        String responseBody = JSON.serialize(result);
        Integer statusCode = result.success ? 200 : 400;
        Logger.finalizeSession(sessionId, responseBody, statusCode);
        Logger.saveAll();

		return result;
	}

	global class CorrectionResponse extends Util_Rest.AbstractRestResult {
		public Decimal creditAmountNotice;
		public Decimal creditAmountDirect;
	}
}