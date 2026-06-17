({
	doInit: function(cmp, event, helper){
		var action = cmp.get('c.getSyncInformation');

		action.setParams({'contextId': cmp.get('v.recordId')});
		action.setCallback(this, function(response){
			cmp.set('v.message', response.getReturnValue());
		});
		$A.enqueueAction(action);
	},
	sync: function(cmp, event, helper){
		//disable button
		event.getSource().set('v.disabled', true);

		var action = cmp.get('c.doSync');
		action.setParams({'contextId': cmp.get('v.recordId')});
		action.setCallback(this, function(response){
			if(response.getReturnValue().length > 0){
				cmp.set('v.message', 'Something went wrong in synchronisation: ' + response.getReturnValue()[0]);
			} else {
				$A.get("e.force:closeQuickAction").fire();
			}
		});
		$A.enqueueAction(action);
	},
	close: function(cmp, event, helper){
		$A.get("e.force:closeQuickAction").fire();
	}
})