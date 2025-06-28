@isTest
private class RCA_MapAttributesTest {
    
    @TestSetup
    static void setup() {
        // Create test products
        List<Product2> products = new List<Product2>();
        products.add(new Product2(
            Name = 'Test Product 1',
            StockKeepingUnit = 'SKU001',
            SBQQ__HasConfigurationAttributes__c = true,
            IsActive = true
        ));
        products.add(new Product2(
            Name = 'Test Product 2',
            StockKeepingUnit = 'SKU002',
            SBQQ__HasConfigurationAttributes__c = true,
            IsActive = true
        ));
        insert products;
        
        // Create configuration attributes
        List<SBQQ__ConfigurationAttribute__c> configAttrs = new List<SBQQ__ConfigurationAttribute__c>();
        for(Product2 p : products) {
            configAttrs.add(new SBQQ__ConfigurationAttribute__c(
                Name = 'Test Attr ' + p.Name,
                SBQQ__Product__c = p.Id,
                SBQQ__TargetField__c = 'Quantity',
                SBQQ__Required__c = true
            ));
        }
        insert configAttrs;
        
        // Create bundle product
        Product2 bundleProduct = new Product2(
            Name = 'Test Bundle Product',
            StockKeepingUnit = 'SKU001 - Bundle',
            IsActive = true
        );
        insert bundleProduct;
    }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        RCA_MapAttributesFromCPQToRCABatch batch = new RCA_MapAttributesFromCPQToRCABatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify products were updated with BasedOnId
        List<Product2> updatedProducts = [SELECT Id, BasedOnId, StockKeepingUnit FROM Product2];
        for(Product2 p : updatedProducts) {
            if(p.StockKeepingUnit != 'SKU001 - Bundle') {
                System.assertNotEquals(null, p.BasedOnId, 'BasedOnId should be populated for product: ' + p.StockKeepingUnit);
            }
        }
    }
    
    @isTest
    static void testBatchWithProductIds() {
        List<Product2> products = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'SKU001'];
        List<Id> productIds = new List<Id>{products[0].Id};
        
        Test.startTest();
        RCA_MapAttributesFromCPQToRCABatch batch = new RCA_MapAttributesFromCPQToRCABatch(productIds);
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify only specified product was processed
        Product2 processedProduct = [SELECT BasedOnId FROM Product2 WHERE Id = :productIds[0]];
        System.assertNotEquals(null, processedProduct.BasedOnId, 'BasedOnId should be populated for specified product');
    }
    
    @isTest
    static void testHelperMethods() {
        List<Product2> products = [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit LIKE 'SKU00%'];
        List<String> errorMessages = new List<String>();
        
        Test.startTest();
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper(errorMessages);
        helper.process(products);
        Test.stopTest();
        
        // Verify records were created
        System.assert([SELECT COUNT() FROM ProductClassification] > 0, 'ProductClassifications should be created');
        System.assert([SELECT COUNT() FROM AttributeDefinition] > 0, 'AttributeDefinitions should be created');
        System.assert([SELECT COUNT() FROM ProductClassificationAttr] > 0, 'Junctions should be created');
        
        // Verify no errors occurred
        System.assertEquals(0, errorMessages.size(), 'No errors should be present');
    }
    
    @isTest
    static void testErrorHandling() {
        // Create product without SKU to trigger errors
        Product2 badProduct = new Product2(
            Name = 'Bad Product',
            SBQQ__HasConfigurationAttributes__c = true,
            IsActive = true
        );
        insert badProduct;
        
        List<String> errorMessages = new List<String>();
        
        Test.startTest();
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper(errorMessages);
        helper.process(new List<Product2>{badProduct});
        Test.stopTest();
        
        // Verify errors were captured
        System.assert(!errorMessages.isEmpty(), 'Error messages should be captured');
    }
    
    @isTest
    static void testPicklistHandling() {
        Product2 prod = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'SKU001' LIMIT 1];
        List<String> errorMessages = new List<String>();
        
        Test.startTest();
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper(errorMessages);
        
        // Test picklist handling by creating a picklist field attribute
        SBQQ__ConfigurationAttribute__c picklistAttr = new SBQQ__ConfigurationAttribute__c(
            Name = 'Picklist Attr',
            SBQQ__Product__c = prod.Id,
            SBQQ__TargetField__c = 'SBQQ__Number__c',
            SBQQ__Required__c = false
        );
        insert picklistAttr;
        
        helper.process(new List<Product2>{prod});
        Test.stopTest();
        
        // Verify picklist-related records were created
        System.assert([SELECT COUNT() FROM AttributePicklist] > 0, 'AttributePicklist should be created');
    }
}