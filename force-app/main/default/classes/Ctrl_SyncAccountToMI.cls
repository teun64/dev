public with sharing class Ctrl_SyncAccountToMI {
	private final Account record;

	public Ctrl_SyncAccountToMI(ApexPages.StandardController stdCont){
		this.record = (Account)stdCont.getRecord();
	}

	public void callMiSync(){
		//String resp = Util_Platform_1.syncAccountToMi(this.record.Id);

		Map<String, String> responses = Util_Platform.syncAccount(this.record.Id, '1');

		
		//if(String.isBlank(resp)){
		if(responses.size() == 0){
			//ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, resp));
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'Account is synchronised!'));
		} else {


			if (responses.containsKey('PlatformSyncException')) {
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'PlatformSyncException' ));
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('PlatformSyncException') ));
			}
			if (responses.containsKey('ConnectionException')) {
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'ConnectionException' ));
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('ConnectionException') ));
			}
			if (responses.containsKey('CustomException')) {
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'CustomException' ));
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('CustomException') ));
			}
			if (responses.containsKey('Exception')) {
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Exception' ));
				ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, responses.get('Exception') ));
			}               
		
		}
	}

}