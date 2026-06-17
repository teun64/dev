({
    doInit : function(component, event, helper){
        var action = component.get("c.handleInit");
        action.setParam("recordId", component.get("v.recordId"));
        action.setCallback(this, function(a) {
            component.set("v.hideSignButton", a.getReturnValue());
        });
        $A.enqueueAction(action);
    },
    doSave: function(component, event, helper) {
        component.set("v.inAction", true);
        var action = component.get("c.handleSave");
        action.setParam("recordId", component.get("v.recordId"));
        action.setCallback(this, function(a) {
            a.getReturnValue();
        });
        $A.enqueueAction(action);
        component.set("v.inAction", false);
    },
    doSign: function(component, event, helper) {
        component.set("v.inAction", true);
        var action = component.get("c.handleSign");
        action.setParam("recordId", component.get("v.recordId"));
        action.setCallback(this, function(a) {
            a.getReturnValue();
        });
        $A.enqueueAction(action);
        component.set("v.inAction", false);
    },
    doCancel : function(component, event, helper) {
        var dismissActionPanel = $A.get("e.force:closeQuickAction");
        dismissActionPanel.fire();
    },
    getAlert : function(cmp, event) {
        // placeholder handler
    }
})
