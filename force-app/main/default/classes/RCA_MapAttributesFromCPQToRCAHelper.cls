public class RCA_MapAttributesFromCPQToRCAHelper {

    private List<String> errors; 

    // Stores picklist codes already present in the system
    private List<String> attrPicklistCodeList = new List<String>();

    // Maps picklist code to corresponding AttributePicklist Id
    private Map<String, Id> attributeCodeAndAttributeIdMap = new Map<String, Id>();

    // Keeps track of product IDs being processed
    private Set<Id> productIds = new Set<Id>();

    // Constructor accepts shared error list from batch
    public RCA_MapAttributesFromCPQToRCAHelper(List<String> sharedErrorList) {
        this.errors = sharedErrorList;
    }

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

        safeInsert(listToInsert);
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

        safeInsert(valuesToInsert);
    }

    /**
     * Creates ProductClassification records and maps them by SKU.
     */
    private List<ProductClassification> createProductClassifications(List<Product2> products) {
        List<ProductClassification> listToInsert = new List<ProductClassification>();
        Set<String> classificationCodes = new Set<String>();
        
        // Build all potential codes
        for (Product2 p : products) {
            classificationCodes.add(p.StockKeepingUnit + '_CLASS');
            productIds.add(p.Id);
        }
    
        // Fetch existing ProductClassifications with those codes
        Map<String, ProductClassification> existingClassifications = new Map<String, ProductClassification>();
        for (ProductClassification pc : [
            SELECT Id, Code 
            FROM ProductClassification 
            WHERE Code IN :classificationCodes
        ]) {
            existingClassifications.put(pc.Code, pc);
        }
    
        // Only insert those that don’t already exist
        for (Product2 p : products) {
            String code = p.StockKeepingUnit + '_CLASS';
            if (!existingClassifications.containsKey(code)) {
                listToInsert.add(new ProductClassification(
                    Name = p.Name + ' Classification',
                    Code = code,
                    Status = 'Active'
                ));
            }
        }
    
        safeInsert(listToInsert);
        return listToInsert;
    }
    

    /**
     * Creates AttributeDefinition records linked to product config attributes.
     */
    private List<AttributeDefinition> createAttributeDefinitions(List<SBQQ__ConfigurationAttribute__c> configAttributes) {
        List<AttributeDefinition> listToInsert = new List<AttributeDefinition>();
        Set<String> attributeCodes = new Set<String>();
    
        // Step 1: Precompute all potential codes
        for (SBQQ__ConfigurationAttribute__c attr : configAttributes) {
            String apiName = attr.Name.replace(' ', '_');
            attributeCodes.add(attr.SBQQ__Product__r.StockKeepingUnit + '_' + apiName);
        }
    
        // Step 2: Query existing AttributeDefinitions by Code
        Map<String, AttributeDefinition> existingAttrDefs = new Map<String, AttributeDefinition>();
        for (AttributeDefinition ad : [
            SELECT Id, Code FROM AttributeDefinition WHERE Code IN :attributeCodes
        ]) {
            existingAttrDefs.put(ad.Code, ad);
        }
    
        // Step 3: Prepare for insert only those that don't exist
        Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.SBQQ__ProductOption__c.fields.getMap();
    
        for (SBQQ__ConfigurationAttribute__c attr : configAttributes) {
            String targetFieldApiName = attr.SBQQ__TargetField__c;
    
            if (fieldsMap.containsKey(targetFieldApiName)) {
                Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(targetFieldApiName).getDescribe();
                String fieldType = fieldDescribe.getType().name();
                String dataType;
    
                switch on fieldType {
                    when 'STRING'  { dataType = 'Text'; }
                    when 'PICKLIST' { dataType = 'Picklist'; }
                    when 'DOUBLE'  { dataType = 'Number'; }
                    when else      { dataType = 'Text'; }
                }
    
                String apiName = attr.Name.replace(' ', '_');
                String code = attr.SBQQ__Product__r.StockKeepingUnit + '_' + apiName;
    
                if (!existingAttrDefs.containsKey(code)) {
                    listToInsert.add(new AttributeDefinition(
                        Name = attr.Name,
                        Label = attr.Name,
                        DataType = dataType, 
                        IsActive = true,
                        IsRequired = attr.SBQQ__Required__c,
                        Code = code,
                        PicklistId = (dataType == 'Picklist') ? attributeCodeAndAttributeIdMap.get(targetFieldApiName) : null
                    ));
                }
            } else {
                System.debug('Target field not found in ProductOption fields: ' + targetFieldApiName);
            }
        }
    
        safeInsert(listToInsert);
        return listToInsert;
    }
    
    

    /**
     * Creates ProductClassificationAttr (junction) records between classifications and attributes.
     */
    private void createProductClassificationAttributes(List<ProductClassification> classifications, List<AttributeDefinition> attrDefs) {
        List<ProductClassificationAttr> listToInsert = new List<ProductClassificationAttr>();
    
        // Collect all possible classification and attribute IDs
        Set<Id> classificationIds = new Set<Id>();
        Set<Id> attributeDefIds = new Set<Id>();
        for (ProductClassification pc : classifications) classificationIds.add(pc.Id);
        for (AttributeDefinition ad : attrDefs) attributeDefIds.add(ad.Id);
    
        // Query existing junctions
        Set<String> existingKeys = new Set<String>();
        for (ProductClassificationAttr existing : [SELECT ProductClassificationId, AttributeDefinitionId FROM ProductClassificationAttr
                    WHERE ProductClassificationId IN :classificationIds AND AttributeDefinitionId IN :attributeDefIds ]) {
                        
                        existingKeys.add(existing.ProductClassificationId + '_' + existing.AttributeDefinitionId);
        }
    
        // Prepare only non-existing ones for insert
        for (ProductClassification pc : classifications) {
            String sku = pc.Code.replace('_CLASS', '');
            for (AttributeDefinition ad : attrDefs) {
                if (ad.Code.startsWith(sku)) {
                    String key = pc.Id + '_' + ad.Id;
                    if (!existingKeys.contains(key)) {
                        listToInsert.add(new ProductClassificationAttr(
                            ProductClassificationId = pc.Id,
                            AttributeDefinitionId = ad.Id,
                            Name = ad.Name
                        ));
                    }
                }
            }
        }
    
        safeInsert(listToInsert);
    }
    

    /**
     * Updates Product2.BasedOnId field with the created classification.
     */
    private void updateProductBasedOnClassifications(List<Product2> products, List<ProductClassification> classifications) {
        List<String> newSKUList = new List<String>();
        for(Product2 product : products){
            String newSku = product.StockKeepingUnit+' - Bundle';
            newSKUList.add(newSku);
        }
        List<Product2> newBundleProducts = [select Id,StockKeepingUnit from Product2 where StockKeepingUnit IN :newSKUList];
        Map<String,Id> newSkuToIdMap = new Map<String,Id>();
        Map<String,Product2> newSkuToProductMap = new Map<String,Product2>();
        for(Product2 prod : newBundleProducts){
            newSkuToIdMap.put(prod.StockKeepingUnit,prod.Id);
            newSkuToProductMap.put(prod.StockKeepingUnit,prod);
        }
        
        Map<String, String> skuToClassIdMap = new Map<String, String>();
        for (ProductClassification pc : classifications) {
            String sku = pc.Code.replace('_CLASS', '');
            skuToClassIdMap.put(sku, pc.Id);
        }

        List<Product2> toUpdate = new List<Product2>();
        for (Product2 prod : products) {
            if (skuToClassIdMap.containsKey(prod.StockKeepingUnit)) {
                String NewProductSku = prod.StockKeepingUnit + ' - Bundle';
                String OldProductSku = prod.StockKeepingUnit;
                
                if(newSkuToIdMap.get(NewProductSku) != null){
                    System.debug('In New Prod PC');
                    newSkuToProductMap.get(NewProductSku).BasedOnId = skuToClassIdMap.get(prod.StockKeepingUnit);
                    toUpdate.add(newSkuToProductMap.get(NewProductSku));

                }else{
                    System.debug('In New Prod PC');
                    prod.BasedOnId = skuToClassIdMap.get(prod.StockKeepingUnit);
                    toUpdate.add(prod);
                }
            }
        }

        safeUpdate(toUpdate);
    }


    /**
     * Helper method to safely insert records and catch errors, adding them to the shared error list.
     */
    private void safeInsert(List<SObject> records) {
        if (records.isEmpty()) return;

        try {
            insert records;
        } catch (DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
                errors.add('Insert failed: ' + e.getDmlMessage(i));
            }
        } catch (Exception e) {
            errors.add('Insert failed: ' + e.getMessage());
        }
    }

    /**
     * Helper method to safely update records and catch errors, adding them to the shared error list.
     */
    private void safeUpdate(List<SObject> records) {
        if (records.isEmpty()) return;

        try {
            update records;
        } catch (DmlException e) {
            for (Integer i = 0; i < e.getNumDml(); i++) {
                errors.add('Update failed: ' + e.getDmlMessage(i));
            }
        } catch (Exception e) {
            errors.add('Update failed: ' + e.getMessage());
        }
    }
}
