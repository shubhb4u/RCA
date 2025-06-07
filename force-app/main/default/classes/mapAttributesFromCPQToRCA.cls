public class mapAttributesFromCPQToRCA implements Database.Batchable<SObject> {
    
    Public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id,Name,SBQQ__HasConfigurationAttributes__c,BasedOnId,StockKeepingUnit ' +
            'FROM Product2 '+
            'WHERE SBQQ__HasConfigurationAttributes__c = true AND ' +
            '(BasedOnId = null OR BasedOnId = \'\')'
        );
    }
    
    public static List<String> attrPicklistCodeList = new List<String>();
    public static Map<String,Id> attributeCodeAndAttributeIdMap = new Map<String,Id>();
    public static Set<Id> productIds = new Set<Id>();
    
    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        
        system.debug('Product List: '+ scope);
        
        handleAttributePicklist();
        
        ProductClassification[] prodClassfications = createProductClassifications(scope);        
        
        SBQQ__ConfigurationAttribute__c[] configAttributes = [SELECT Id,Name,SBQQ__Product__c,SBQQ__Product__r.StockKeepingUnit,SBQQ__Required__c,SBQQ__TargetField__c
                                                              FROM SBQQ__ConfigurationAttribute__c
                                                              WHERE SBQQ__Product__c =: productIds];
        
        
        
        AttributeDefinition[] attributeDefs = createAttributeDefinations(configAttributes);
        
        createProductClassificationAttributes(prodClassfications,attributeDefs);
        
        List<Product2> updateProducts = new List<Product2>();
        Map<String,String> prodSKUAndProdClassIdMap = getProdSKUAndProdClassIdMap(prodClassfications);
        
        for(Product2 prod :scope) {
            if(prodSKUAndProdClassIdMap.containsKey(prod.StockKeepingUnit) && prodSKUAndProdClassIdMap.get(prod.StockKeepingUnit) != null) {
                prod.BasedOnId = prodSKUAndProdClassIdMap.get(prod.StockKeepingUnit);
                updateProducts.add(prod);
            }
        }
        if(updateProducts.size() > 0) {
            update updateProducts;
        }
    }
    
    public static void handleAttributePicklist() {
        
        Schema.DescribeFieldResult targetField = SBQQ__ConfigurationAttribute__c.SBQQ__TargetField__c.getDescribe();
        
        if (targetField.getType() == Schema.DisplayType.Picklist) {
            
            List<Schema.PicklistEntry> picklistValues = targetField.getPicklistValues();
            
            AttributePicklist[] existingAttributesPicklist = [SELECT Id,Code FROM AttributePicklist];
            
            for(AttributePicklist attrPicklist :existingAttributesPicklist) {
                attrPicklistCodeList.add(attrPicklist.Code);
                attributeCodeAndAttributeIdMap.put(attrPicklist.Code,attrPicklist.Id);
            }
            
            List<AttributePicklist> attributesPicklistToCreate = createAttributePicklist(picklistValues);
            
            if(attributesPicklistToCreate.size() > 0) {
                
                for(AttributePicklist attrPickList: attributesPicklistToCreate) {
                    system.debug('Attribute Picklist: '+ attrPickList);
                    attributeCodeAndAttributeIdMap.put(attrPickList.Code,attrPickList.Id);
                }
                system.debug('attributeCodeAndAttributeIdMap: '+ attributeCodeAndAttributeIdMap);
                
                createAttributePicklistValues(picklistValues);
            }
        }
    }
    
    public static List<AttributePicklist> createAttributePicklist(List<Schema.PicklistEntry> picklistValues) {
        
        List<AttributePicklist> attributesPicklistToCreate = new List<AttributePicklist>();
        
        for (Schema.PicklistEntry val : picklistValues) {
            
            String attributeName = val.getValue();
            String attributeLabel = val.getLabel();
            System.debug('Target Field - Label: ' + attributeName + ', Value (Field Name): ' + attributeName);
            
            if(attributeName == 'Unit Price' || 
               attributeName == 'Discount (Amt)' || 
               attributeName == 'Discount (%)' ||
               attrPicklistCodeList.contains(attributeName)) {
                   continue;
               }
            
            AttributePicklist currentAttributePicklist = new AttributePicklist();
            currentAttributePicklist.Name = attributeLabel;
            currentAttributePicklist.Code = attributeName;
            currentAttributePicklist.Status = 'Active';
            currentAttributePicklist.DataType = 'Text';
            attributesPicklistToCreate.add(currentAttributePicklist);
        }
        
        if(attributesPicklistToCreate.size() > 0) {
            system.debug('Attributes Picklist to Create: '+ attributesPicklistToCreate);
            insert attributesPicklistToCreate;
        }
        
        return attributesPicklistToCreate; 
    }
    
    public static void createAttributePicklistValues(List<Schema.PicklistEntry> picklistValues) {
        
        List<AttributePicklistValue> attributesPicklistValuesToCreate = new List<AttributePicklistValue>();
        
        // Dynamically get describe info for SBQQ__ProductOption__c.<fieldName>
        Map<String, Schema.SObjectField> optionFieldsMap = Schema.SObjectType.SBQQ__ProductOption__c.fields.getMap(); // Key: Product Option Field, Value: Field Data
        
        for (Schema.PicklistEntry val : picklistValues) {
            
            String attributeName = val.getValue();
            String attributeLabel = val.getLabel();
            System.debug('Target Field - Label: ' + attributeName + ', Value (Field Name): ' + attributeName);
            
            if(attributeName == 'Unit Price' || 
               attributeName == 'Discount (Amt)' || 
               attributeName == 'Discount (%)' ||
               attrPicklistCodeList.contains(attributeName)) {
                   continue;
               }
            
            if (optionFieldsMap.containsKey(attributeName)) {
                Schema.DescribeFieldResult attributeFieldDescribe = optionFieldsMap.get(attributeName).getDescribe();
                
                if (attributeFieldDescribe.getType() == Schema.DisplayType.Picklist) {
                    List<Schema.PicklistEntry> optionPicklistValues = attributeFieldDescribe.getPicklistValues();
                    
                    for (Schema.PicklistEntry pickVal : optionPicklistValues) {
                        
                        String attributeFieldValue = pickVal.getValue();
                        String attributeFieldLabel = pickVal.getLabel();
                        System.debug('-- Attribute Name: ' + attributeName + ', Attribute Field Value: ' + attributeFieldValue + ', Attribute Field Label: ' + attributeFieldLabel);
                        
                        if(attributeCodeAndAttributeIdMap.containsKey(attributeName)) {
                            AttributePicklistValue currentPicklistValue = new AttributePicklistValue();
                            currentPicklistValue.Name = attributeFieldLabel;
                            currentPicklistValue.Code = attributeName + '_' + attributeFieldValue;
                            currentPicklistValue.Value = attributeFieldValue;
                            currentPicklistValue.Status = 'Active';
                            currentPicklistValue.PicklistId = attributeCodeAndAttributeIdMap.get(attributeName);
                            attributesPicklistValuesToCreate.add(currentPicklistValue);
                        }
                    }
                }
            }
        }
        
        if(attributesPicklistValuesToCreate.size() > 0) {
            system.debug('Attributes Picklist Values to Create: '+ attributesPicklistValuesToCreate);
            insert attributesPicklistValuesToCreate;
        }
    }
    
    public static List<ProductClassification> createProductClassifications(List<Product2> products) {
        
        ProductClassification[] prodClassfications = new List<ProductClassification>();
        
        for (Product2 prod : products) {
            
            ProductClassification prodClass = new ProductClassification();
            prodClass.Name = prod.Name + ' Classification';
            prodClass.Code = prod.StockKeepingUnit + '_CLASS';
            prodClass.Status = 'Active';
            
            prodClassfications.add(prodClass);
            productIds.add(prod.Id);
        }
        if(prodClassfications.size() > 0) {
            insert prodClassfications;
        }
        
        return prodClassfications;
    }
    
    public static List<AttributeDefinition> createAttributeDefinations(List<SBQQ__ConfigurationAttribute__c> configAttributes) {
        
        AttributeDefinition[] attributeDefs = new List<AttributeDefinition>();
        
        for(SBQQ__ConfigurationAttribute__c configAttr :configAttributes) {
            String configName = configAttr.Name;
            String apiName = configName.replace(' ','_');
            system.debug('Api Name: '+apiName);
            AttributeDefinition attrDef = new AttributeDefinition();
            attrDef.Name = configName;
            attrDef.Label = configName;
            attrDef.DeveloperName = apiName;
            attrDef.DataType = 'Picklist';
            attrDef.IsActive = true;
            attrDef.IsRequired = configAttr.SBQQ__Required__c;
            attrDef.Code = configAttr.SBQQ__Product__r.StockKeepingUnit + '_' + apiName;
            attrDef.PicklistId = attributeCodeAndAttributeIdMap.get(configAttr.SBQQ__TargetField__c);
            attributeDefs.add(attrDef);
        }
        
        if(attributeDefs.size() > 0) {
            insert attributeDefs;
        }
        
        return attributeDefs;
    }
    
    public static void createProductClassificationAttributes(List<ProductClassification> prodClassfications,List<AttributeDefinition> attributeDefs) {
        
        ProductClassificationAttr[] prodClassAttributes = new List<ProductClassificationAttr>();
        
        for(ProductClassification prodClass :prodClassfications) {
            String prodSKUFromProdClass = prodClass.Code.substring(0, prodClass.Code.length() - 6);
            Integer prodSKULength = prodSKUFromProdClass.length();
            for(AttributeDefinition attrDef :attributeDefs) {
                String prodSKUFromAttrDef = attrDef.Code.substring(0, prodSKULength);
                if(prodSKUFromProdClass == prodSKUFromAttrDef) {
                    ProductClassificationAttr prodClassAttr = new ProductClassificationAttr();
                    prodClassAttr.ProductClassificationId = prodClass.Id;
                    prodClassAttr.AttributeDefinitionId = attrDef.Id;
                    prodClassAttr.Name = attrDef.Name;
                    prodClassAttributes.add(prodClassAttr);
                }
            }
        }
        if(prodClassAttributes.size() > 0) {
            insert prodClassAttributes;
        }
    }
    
    public static Map<String,String> getProdSKUAndProdClassIdMap(List<ProductClassification> prodClassfications) {
        
        Map<String,String> prodSKUAndProdClassIdMap = new Map<String,String>();
        
        for(ProductClassification prodClass :prodClassfications) {
            String prodSKU = prodClass.Code.substring(0, prodClass.Code.length() - 6);
            prodSKUAndProdClassIdMap.put(prodSKU,prodClass.Id);
        }
        
        return prodSKUAndProdClassIdMap;
    }
    
    public void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed.');
    }
}