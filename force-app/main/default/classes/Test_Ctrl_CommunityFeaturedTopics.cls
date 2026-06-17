@isTest(seeAllData=true)
public class Test_Ctrl_CommunityFeaturedTopics {
    
    @isTest
    static void testGetFeaturedTopicsWithData() {
        // Step 1: Call the method to test
        Test.startTest();
        List<Ctrl_CommunityFeaturedTopics.TopicWrapper> results = Ctrl_CommunityFeaturedTopics.getFeaturedTopics();
        Test.stopTest();

        // Step 2: Validate the results
        System.assertNotEquals(0, results.size(), 'Expected at least one topic wrapper to be returned.');

        // Assuming the first result matches an existing topic, you can validate against it
        Ctrl_CommunityFeaturedTopics.TopicWrapper wrapper = results[0]; // Get the first wrapper for validation
        
        // Fetch the topic from existing data
        Topic featuredTopic = [SELECT Id, Name, Description FROM Topic WHERE Id = :wrapper.Id LIMIT 1];
        
        System.assertEquals(featuredTopic.Id, wrapper.Id, 'Topic Id should match.');
        System.assertEquals(featuredTopic.Name, wrapper.Name, 'Topic Name should match.');
        System.assertEquals(featuredTopic.Description, wrapper.Description, 'Topic Description should match.');
    }
}