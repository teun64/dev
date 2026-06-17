public class Ctrl_OAuth {
	public final OAuth_Token__c record {get; private set;}
	// private Util_OAuth oauth;
	public String action {get; private set;}

	public Ctrl_OAuth(ApexPages.StandardController stdC) {
		this.record = (OAuth_Token__c)stdC.getRecord();

		//if we have a code on the GET (we got back here from the external system)
		//set the action to 'getRefreshToken'
		this.action = 'authorize';
		if(ApexPages.currentPage().getParameters().containsKey('code')){
			this.action = 'getRefreshToken';
		}

		//this.oauth = Util_OAuth.getInstance(this.record, null);
	}

	public String getCurrentUrl(){
		PageReference pr = Page.OAuth;
		return 'https://' + System.URL.getOrgDomainUrl().getHost() + pr.getUrl();
	}

	public PageReference getRefreshToken(){
		String code = ApexPages.currentPage().getParameters().get('code');
		String retUri = this.getCurrentUrl()+'?Id='+this.record.Id;
		/*if(this.oauth.getRefreshToken(code, retUri)){
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.CONFIRM, 'The new refresh and access token have been stored.'));
		} else {
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.FATAL, 'Something went wrong'));
		}*/
		return new PageReference('/' + this.record.Id);
	}
}