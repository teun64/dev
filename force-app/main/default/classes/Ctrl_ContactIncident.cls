public with sharing class Ctrl_ContactIncident {
	public Contact cont;
	public List<Ctrl_ContactIncident.Mail> miMsgs {get;set;}

	public Ctrl_ContactIncident(ApexPages.StandardController stdController) {
		Contact cont = [SELECT Id, Name, extId_1__c FROM Contact WHERE Id = :stdController.getId()];
        String endPoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Email_Endpoint'].value__c;
		String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, cont.extId_1__c);

        MiMails miEmails = (MiMails) JSON.deserialize('{' + '"mails": ' + resBody + '}', MiMails.class);
        miMsgs = miEmails.mails;
        miMsgs.sort();
    }

    public class MiMails {
    	public List<Mail> mails {get;set;}
    }

    public class Mail implements Comparable {
        public String id {get;set;}
        public String toContactId {get;set;}
        public String toAddress {get;set;}
        public String ccAddresses {get;set;}
        public String subject {get;set;}
        public String body {get;set;}
        public Long sentDate {get;set;}

        public Datetime getConvertedDate(){
        	return Datetime.newInstance(this.sentDate*1000);
        }

       	public Integer compareTo(Object compareTo){
    		Mail compareToMail = (Mail) compareTo;

	    	if(this.sentDate < compareToMail.sentDate){
	    		return 1;
	    	} 
	    	
	    	return -1;
    	}
    }
}