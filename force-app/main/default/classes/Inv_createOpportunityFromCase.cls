public with sharing class Inv_createOpportunityFromCase {

    @InvocableMethod(
        label='Create Opportunity from Case'
        description='Creates an Opportunity linked to a Case. Requires the Case to have an Account. Defaults to the Standard record type, sets the first active stage, closes in 30 days, and enables Require Signature.'
        category='Opportunity'
    )
    public static List<Results> createOpportunity(List<Requests> requestList) {
        Results response = new Results();

        if (requestList.isEmpty()) {
            response.isSuccess = false;
            response.errorMessage = 'No input provided.';
            return new List<Results>{ response };
        }

        Requests req = requestList[0];
        String recordTypeName = String.isBlank(req.recordTypeName) ? 'Standard' : req.recordTypeName;

        List<Case> cases = [
            SELECT Id, AccountId, Account.Name, CaseNumber
            FROM Case
            WHERE Id = :req.caseId
            LIMIT 1
        ];

        if (cases.isEmpty()) {
            response.isSuccess = false;
            response.errorMessage = 'Case not found.';
            return new List<Results>{ response };
        }

        Case c = cases[0];

        if (c.AccountId == null) {
            response.isSuccess = false;
            response.errorMessage = 'Cannot create an Opportunity: the Case has no Account. Please add an Account to the Case first.';
            return new List<Results>{ response };
        }

        List<OpportunityStage> stages = [
            SELECT MasterLabel
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder ASC
            LIMIT 1
        ];

        if (stages.isEmpty()) {
            response.isSuccess = false;
            response.errorMessage = 'No active Opportunity stages found.';
            return new List<Results>{ response };
        }

        RecordTypeInfo rtInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(recordTypeName);

        if (rtInfo == null) {
            response.isSuccess = false;
            response.errorMessage = 'Record type not found: ' + recordTypeName;
            return new List<Results>{ response };
        }

        Opportunity opp = new Opportunity(
            Name                     = c.Account.Name + ' - ' + c.CaseNumber,
            AccountId                = c.AccountId,
            Case__c                  = c.Id,
            RecordTypeId             = rtInfo.getRecordTypeId(),
            StageName                = stages[0].MasterLabel,
            CloseDate                = Date.today().addDays(30),
            Option_Require_Signature__c = true
        );

        try {
            insert opp;
            response.isSuccess = true;
            response.opportunityId = opp.Id;
            response.opportunityName = opp.Name;
        } catch (Exception e) {
            response.isSuccess = false;
            response.errorMessage = 'Failed to create Opportunity: ' + e.getMessage();
        }

        return new List<Results>{ response };
    }

    public class Requests {
        @InvocableVariable(label='Case ID' description='ID of the Case to link the new Opportunity to.' required=true)
        public String caseId;

        @InvocableVariable(label='Record Type Developer Name' description='Developer name of the Opportunity record type. Defaults to Standard.')
        public String recordTypeName;
    }

    public class Results {
        @InvocableVariable(label='Is Success' description='True when the Opportunity was created successfully.')
        public Boolean isSuccess;

        @InvocableVariable(label='Opportunity ID' description='ID of the newly created Opportunity.')
        public String opportunityId;

        @InvocableVariable(label='Opportunity Name' description='Name of the newly created Opportunity.')
        public String opportunityName;

        @InvocableVariable(label='Error Message' description='Populated when creation fails.')
        public String errorMessage;
    }
}
