public class Util_Flows{
    
    @InvocableMethod(label='doFlow' description='Runs a automated flow with a recordID as parameter' category='Flows')
    public static void doFlow2(List<Util_Flows.FlowInputs> inputs) {       
    
        for (Util_Flows.FlowInputs input : inputs) {
            // Create flow variable map
            Map<String, Object> variables = new Map<String, Object> {
                'recordID' => input.recordID
            };
            // Start flow interview
            Flow.Interview myFlow = Flow.Interview.createInterview(input.flowName, variables);
            myFlow.start();
        }
    }
    
    //input details that comes to apex from flow
    public class FlowInputs{
    
        @InvocableVariable(required=true)
        public string flowName;
        
        @InvocableVariable(required=true)
        public String recordID;       
    }
}