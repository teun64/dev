public without sharing class Ctrl_CommunityFeaturedTopics {
    @AuraEnabled(cacheable=true)
    public static List<TopicWrapper> getFeaturedTopics() {
        List<TopicWrapper> topicWrappers = new List<TopicWrapper>();

        // Check CRUD permissions
        if (!Schema.sObjectType.Topic.isAccessible()) {
            return topicWrappers; // Return empty if the user cannot access the Topic object
        }

        // Query for featured topics
        List<Topic> topics = [SELECT Id, Name, Description FROM Topic WHERE ManagedTopicType LIKE '%Featured%'];

        // Populate TopicWrapper list
        for (Topic topic : topics) {
            TopicWrapper wrapper = new TopicWrapper();
            wrapper.id = topic.Id;
            wrapper.name = topic.Name;
            wrapper.description = topic.Description;

            // Set icon URL if a custom brand asset is available
            wrapper.iconUrl = getCustomBrandIconUrl(topic.Id);

            topicWrappers.add(wrapper);
        }

        return topicWrappers;
    }

    private static String getCustomBrandIconUrl(Id topicId) {


        List<CustomBrand> customBrands = [SELECT Id FROM CustomBrand WHERE ParentId = :topicId LIMIT 1];
        if (!customBrands.isEmpty()) {
            CustomBrand customBrand = customBrands[0];
            // Check CRUD permission for CustomBrandAsset

            List<CustomBrandAsset> brandAssets = [SELECT AssetSourceId FROM CustomBrandAsset WHERE CustomBrandId = :customBrand.Id LIMIT 1];
            if (!brandAssets.isEmpty()) {
                // Check CRUD permission for ContentAsset

                List<ContentAsset> assets = [SELECT DeveloperName FROM ContentAsset WHERE Id = :brandAssets[0].AssetSourceId LIMIT 1];
                return assets.isEmpty() ? null : '/sfsites/c/file-asset/' + assets[0].DeveloperName;
            }
        }
        return null;
    }

    // Wrapper class to structure data for LWC
    public class TopicWrapper {
        @AuraEnabled public String id;          // Changed from Id to id
        @AuraEnabled public String name;        // Changed from Name to name
        @AuraEnabled public String description;  // Changed from Description to description
        @AuraEnabled public String iconUrl;
    }
}