global class configAttributesFromCPQToRca implements Database.Batchable<SObject>{
    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id,Name,SBQQ__HasConfigurationAttributes__c FROM Product2 where SBQQ__HasConfigurationAttributes__c =true and type!=bundle'//Type filter is not required
        );
    }
    global void execute(Database.BatchableContext bc, List<Product2> scope) {
        // Create a map to hold productId -> List of Configuration Attributes
        Map<Id, List<SBQQ__ConfigurationAttribute__c>> productToAttributes = new Map<Id, List<SBQQ__ConfigurationAttribute__c>>();
        List<String> attributepicklistsNames = new List<String>(); // holds the names of configuration Attributes
        
        // Collect all product Ids
        Set<Id> productIds = new Set<Id>();
        for (Product2 prod : scope) {
            productIds.add(prod.Id);
        }
        
        // Query all related Configuration Attributes in one go
        List<SBQQ__ConfigurationAttribute__c> allAttributes = [
            SELECT Name, SBQQ__Product__c 
            FROM SBQQ__ConfigurationAttribute__c 
            WHERE SBQQ__Product__c IN :productIds
        ];
        
        // Populate the map
        for (SBQQ__ConfigurationAttribute__c attr : allAttributes) {
            if (!productToAttributes.containsKey(attr.SBQQ__Product__c)) {
                productToAttributes.put(attr.SBQQ__Product__c, new List<SBQQ__ConfigurationAttribute__c>());
            }
            productToAttributes.get(attr.SBQQ__Product__c).add(attr);
        }
        for (Id productId : productToAttributes.keySet()) {
            
            List<SBQQ__ConfigurationAttribute__c> attributes = productToAttributes.get(productId);
            
            for (SBQQ__ConfigurationAttribute__c attr : attributes) {
                
                attributepicklistsNames.add(attr.Name);
            }
        }
        List<AttributePicklist> attributePicklist = new List<AttributePicklist>();
        integer i =100;
        for(String s : attributepicklistsNames){
            AttributePicklist att = new AttributePicklist();
            att.Name= s;
            att.Code=s+i; 
            att.Status='Active';
            att.DataType= 'Text';
            attributePicklist.add(att);
            i++;
        }
        for(AttributePicklist ap : attributePicklist){
            System.debug(ap.Name+'   '+ap.Code+'   '+ap.Status+'    '+ap.DataType);
        }
        insert attributePicklist;
    }
    global void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed.');
    }
}