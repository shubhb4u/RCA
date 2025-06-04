public class RCA_MapAttributesFromCPQToRCAHelper {

    // Stores picklist codes already present in the system
    private List<String> attrPicklistCodeList = new List<String>();

    // Maps picklist code to corresponding AttributePicklist Id
    private Map<String, Id> attributeCodeAndAttributeIdMap = new Map<String, Id>();

    // Keeps track of product IDs being processed
    private Set<Id> productIds = new Set<Id>();

    /**
     * Main entry point for processing a batch of Product2 records.
     */
    public void process(List<Product2> scope) {

        // Step 1: Handle picklist metadata and insert new picklist values if needed
        handleAttributePicklist();

        // Step 2: Create Product Classification records for each product
        List<ProductClassification> prodClassfications = createProductClassifications(scope);

        // Step 3: Fetch Configuration Attributes related to products
        List<SBQQ__ConfigurationAttribute__c> configAttributes = [
            SELECT Id, Name, SBQQ__Product__c, SBQQ__Product__r.StockKeepingUnit,
                   SBQQ__Required__c, SBQQ__TargetField__c
            FROM SBQQ__ConfigurationAttribute__c
            WHERE SBQQ__Product__c IN :productIds
        ];

        // Step 4: Create Attribute Definitions from Config Attributes
        List<AttributeDefinition> attributeDefs = createAttributeDefinitions(configAttributes);

        // Step 5: Create junctions between Product Classifications and Attribute Definitions
        createProductClassificationAttributes(prodClassfications, attributeDefs);

        // Step 6: Update Products with BasedOnId referring to their Classification
        updateProductBasedOnClassifications(scope, prodClassfications);
    }

    /**
     * Checks the ConfigurationAttribute target field for picklists and sets up values in RCA.
     */
    private void handleAttributePicklist() {
        Schema.DescribeFieldResult targetField = SBQQ__ConfigurationAttribute__c.SBQQ__TargetField__c.getDescribe();

        if (targetField.getType() == Schema.DisplayType.Picklist) {
            List<Schema.PicklistEntry> picklistValues = targetField.getPicklistValues();

            // Fetch existing AttributePicklist entries
            for (AttributePicklist ap : [SELECT Id, Code FROM AttributePicklist]) {
                attrPicklistCodeList.add(ap.Code);
                attributeCodeAndAttributeIdMap.put(ap.Code, ap.Id);
            }

            // Insert new AttributePicklist entries if needed
            List<AttributePicklist> toInsert = createAttributePicklist(picklistValues);
            for (AttributePicklist ap : toInsert) {
                attributeCodeAndAttributeIdMap.put(ap.Code, ap.Id);
            }

            // Insert AttributePicklistValue entries
            createAttributePicklistValues(picklistValues);
        }
    }

    /**
     * Inserts new AttributePicklist records for picklist fields not already present.
     */
    private List<AttributePicklist> createAttributePicklist(List<Schema.PicklistEntry> picklistValues) {
        List<AttributePicklist> listToInsert = new List<AttributePicklist>();

        for (Schema.PicklistEntry val : picklistValues) {
            String valCode = val.getValue();
            if (valCode == 'Unit Price' || valCode == 'Discount (Amt)' || valCode == 'Discount (%)' ||
                attrPicklistCodeList.contains(valCode)) continue;

            listToInsert.add(new AttributePicklist(
                Name = val.getLabel(),
                Code = valCode,
                Status = 'Active',
                DataType = 'Text'
            ));
        }

        if (!listToInsert.isEmpty()) insert listToInsert;
        return listToInsert;
    }

    /**
     * Inserts AttributePicklistValue records for each picklist value in the CPQ schema.
     */
    private void createAttributePicklistValues(List<Schema.PicklistEntry> picklistValues) {
        List<AttributePicklistValue> valuesToInsert = new List<AttributePicklistValue>();
        Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.SBQQ__ProductOption__c.fields.getMap();

        for (Schema.PicklistEntry val : picklistValues) {
            String valCode = val.getValue();
            if (valCode == 'Unit Price' || valCode == 'Discount (Amt)' || valCode == 'Discount (%)' ||
                attrPicklistCodeList.contains(valCode)) continue;

            if (fieldsMap.containsKey(valCode)) {
                Schema.DescribeFieldResult fieldDesc = fieldsMap.get(valCode).getDescribe();
                if (fieldDesc.getType() == Schema.DisplayType.Picklist) {
                    for (Schema.PicklistEntry pickVal : fieldDesc.getPicklistValues()) {
                        if (!attributeCodeAndAttributeIdMap.containsKey(valCode)) continue;

                        valuesToInsert.add(new AttributePicklistValue(
                            Name = pickVal.getLabel(),
                            Code = valCode + '_' + pickVal.getValue(),
                            Value = pickVal.getValue(),
                            Status = 'Active',
                            PicklistId = attributeCodeAndAttributeIdMap.get(valCode)
                        ));
                    }
                }
            }
        }

        if (!valuesToInsert.isEmpty()) insert valuesToInsert;
    }

    /**
     * Creates ProductClassification records and maps them by SKU.
     */
    private List<ProductClassification> createProductClassifications(List<Product2> products) {
        List<ProductClassification> listToInsert = new List<ProductClassification>();
        for (Product2 p : products) {
            listToInsert.add(new ProductClassification(
                Name = p.Name + ' Classification',
                Code = p.StockKeepingUnit + '_CLASS',
                Status = 'Active'
            ));
            productIds.add(p.Id);
        }

        if (!listToInsert.isEmpty()) insert listToInsert;
        return listToInsert;
    }

    /**
     * Creates AttributeDefinition records linked to product config attributes.
     */
    private List<AttributeDefinition> createAttributeDefinitions(List<SBQQ__ConfigurationAttribute__c> configAttributes) {
        List<AttributeDefinition> listToInsert = new List<AttributeDefinition>();

        for (SBQQ__ConfigurationAttribute__c attr : configAttributes) {
            String apiName = attr.Name.replace(' ', '_');

            listToInsert.add(new AttributeDefinition(
                Name = attr.Name,
                Label = attr.Name,
                DeveloperName = apiName,
                DataType = 'Picklist',
                IsActive = true,
                IsRequired = attr.SBQQ__Required__c,
                Code = attr.SBQQ__Product__r.StockKeepingUnit + '_' + apiName,
                PicklistId = attributeCodeAndAttributeIdMap.get(attr.SBQQ__TargetField__c)
            ));
        }

        if (!listToInsert.isEmpty()) insert listToInsert;
        return listToInsert;
    }

    /**
     * Creates ProductClassificationAttr (junction) records between classifications and attributes.
     */
    private void createProductClassificationAttributes(List<ProductClassification> classifications, List<AttributeDefinition> attrDefs) {
        List<ProductClassificationAttr> listToInsert = new List<ProductClassificationAttr>();

        for (ProductClassification pc : classifications) {
            String sku = pc.Code.replace('_CLASS', '');
            for (AttributeDefinition ad : attrDefs) {
                if (ad.Code.startsWith(sku)) {
                    listToInsert.add(new ProductClassificationAttr(
                        ProductClassificationId = pc.Id,
                        AttributeDefinitionId = ad.Id,
                        Name = ad.Name
                    ));
                }
            }
        }

        if (!listToInsert.isEmpty()) insert listToInsert;
    }

    /**
     * Updates Product2.BasedOnId field with the created classification.
     */
    private void updateProductBasedOnClassifications(List<Product2> products, List<ProductClassification> classifications) {
        Map<String, String> skuToClassIdMap = new Map<String, String>();
        for (ProductClassification pc : classifications) {
            String sku = pc.Code.replace('_CLASS', '');
            skuToClassIdMap.put(sku, pc.Id);
        }

        List<Product2> toUpdate = new List<Product2>();
        for (Product2 prod : products) {
            if (skuToClassIdMap.containsKey(prod.StockKeepingUnit)) {
                prod.BasedOnId = skuToClassIdMap.get(prod.StockKeepingUnit);
                toUpdate.add(prod);
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
    }
}
