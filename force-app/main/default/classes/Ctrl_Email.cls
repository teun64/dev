public with sharing class Ctrl_Email {
	public List<Ctrl_Email.Mail> miMsgs {get; private set;}

	public Ctrl_Email(ApexPages.StandardController stdController) {
		try { 
			Contact cont = [SELECT Id, Name, extId_1__c FROM Contact WHERE Id = :stdController.getId()];
			String endpoint = [SELECT Value__c FROM Mi_Sync_Setting__mdt WHERE DeveloperName = 'Email_Endpoint'].value__c;
			String resBody = Util_RequestButtons.getMiHttpResponse(endpoint, cont.extId_1__c);

			this.miMsgs = (List<Ctrl_Email.Mail>) JSON.deserialize(resBody, List<Ctrl_Email.Mail>.class);
			this.miMsgs.sort();
            this.miMsgs = Ctrl_Email.generateNSizeList(1000, this.miMsgs);
            
		} catch (Exception e){
			ApexPages.addMessages(e);
		}
	}

    private static List<Ctrl_Email.Mail> generateNSizeList(Integer length, List<Ctrl_Email.Mail> objectList){
        if(objectList.size() < length){
            return objectList;
        }

        List<Ctrl_Email.Mail> tmpList = new List<Ctrl_Email.Mail>();
        for(Integer i = 0; i < length; i++){
            tmpList.add(objectList[i]);
        }

        return tmpList;
    }

	private class Mail implements Comparable {
		public String id {get; private set;}
		public String toContactId {get; private set;}
		public String toAddress {get; private set;}
		public String ccAddresses {get; private set;}
		public String subject {get; private set;}
		public String body {get; private set;}
		public Long sentDate {get; private set;}

		public String getConvertedDate(){
			return this.sentDate != null ? Datetime.newInstance(this.sentDate*1000).format('EEE dd-MM-YYYY HH:mm:ss') : null;
		}

	   	public Integer compareTo(Object compareTo){
			Ctrl_Email.Mail compareToMail = (Ctrl_Email.Mail) compareTo;
			
			return this.sentDate < compareToMail.sentDate ? 1 : -1;
		}
	}
}