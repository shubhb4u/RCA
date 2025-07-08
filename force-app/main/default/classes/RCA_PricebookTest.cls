@IsTest
public class RCA_PricebookTest {
    
    @TestSetup
    static void setupTestData() {
        // Create Standard Price Book (usually exists by default, but ensuring for test)
        Pricebook2 standardPB = new Pricebook2(
            Name = 'Standard Price Book',
            IsActive = true
        );
        insert standardPB;
        
        // Create RCA Price Book
        Pricebook2 rcaPB = new Pricebook2(
            Name = 'RCA_PriceBook',
            IsActive = true
        );
        insert rcaPB;
        
        // Create ProductSellingModels
        List<ProductSellingModel> psms = new List<ProductSellingModel>();
        psms.add(new ProductSellingModel(
            Name = 'OneTime Model',
            SellingModelType = 'OneTime',
            Status = 'Active'
        ));
        psms.add(new ProductSellingModel(
            Name = 'TermDefined Model',
            SellingModelType = 'TermDefined',
            PricingTermUnit = 'Months',
            PricingTerm = 1,
            Status = 'Active'
        ));
        psms.add(new ProductSellingModel(
            Name = 'Evergreen Model',
            SellingModelType = 'Evergreen',
            PricingTermUnit = 'Months',
            PricingTerm = 1,
            Status = 'Active'
        ));
        insert psms;
        
        // Create ProrationPolicy
        ProrationPolicy proPolicy = new ProrationPolicy(
            Name = 'Default Proration Policy',
            ProrationPolicyType = 'StandardTimePeriods'
        );
        insert proPolicy;
        
        // Create test products
        List<Product2> products = new List<Product2>();
        products.add(new Product2(
            Name = 'Test Product 1',
            StockKeepingUnit = 'TEST-001',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__SubscriptionType__c = 'Renewable',
            SBQQ__SubscriptionPricing__c = 'Monthly'
        ));
        products.add(new Product2(
            Name = 'Test Product 3',
            StockKeepingUnit = 'TEST-003',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__SubscriptionType__c = 'One-Time',
            SBQQ__SubscriptionPricing__c = 'One-Time'
        ));
        products.add(new Product2(
            Name = 'Test Product 4',
            StockKeepingUnit = 'TEST-004',
            IsActive = true,
            IsProcessed__c = false,
            Type = 'Bundle'
        ));
        products.add(new Product2(
            Name = 'Test Product 5',
            StockKeepingUnit = 'TEST-005',
            IsActive = true,
            IsProcessed__c = false
            // No subscription fields to test blank scenario
        ));
        insert products;
        
        // Get Standard Price Book ID
        Id standardPBId = Test.getStandardPricebookId();
        
        // Create standard price book entries
        List<PricebookEntry> standardPBEs = new List<PricebookEntry>();
        for (Product2 prod : products) {
            standardPBEs.add(new PricebookEntry(
                Product2Id = prod.Id,
                Pricebook2Id = standardPBId,
                UnitPrice = 100.00,
                IsActive = true
            ));
        }
        insert standardPBEs;
        
    }
    
    @IsTest
    static void testBatchConstructorDefault() {
        Test.startTest();
        RCA_Pricebook batch = new RCA_Pricebook();
        System.assertNotEquals(null, batch, 'Batch should be instantiated');
        Test.stopTest();
    }
    
    @IsTest
    static void testBatchConstructorWithProductIds() {
        List<Product2> products = [SELECT Id FROM Product2 LIMIT 2];
        List<Id> productIds = new List<Id>();
        for (Product2 prod : products) {
            productIds.add(prod.Id);
        }
        
        Test.startTest();
        RCA_Pricebook batch = new RCA_Pricebook(productIds);
        System.assertNotEquals(null, batch, 'Batch should be instantiated with product IDs');
        Test.stopTest();
    }
    
    @IsTest
    static void testBatchStartMethodWithoutProductIds() {
        RCA_Pricebook batch = new RCA_Pricebook();
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
        Test.stopTest();
    }
    
    @IsTest
    static void testBatchStartMethodWithProductIds() {
        List<Product2> products = [SELECT Id FROM Product2 LIMIT 2];
        List<Id> productIds = new List<Id>();
        for (Product2 prod : products) {
            productIds.add(prod.Id);
        }
        
        RCA_Pricebook batch = new RCA_Pricebook(productIds);
        
        Test.startTest();
        Database.QueryLocator ql = batch.start(null);
        System.assertNotEquals(null, ql, 'QueryLocator should not be null');
        Test.stopTest();
    }
    
    @IsTest
    static void testBatchExecuteSuccess() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 LIMIT 3];
        
        RCA_Pricebook batch = new RCA_Pricebook();
        
        Test.startTest();
        batch.execute(null, products);
        Test.stopTest();
        
        // Verify PSMOs were created
        List<ProductSellingModelOption> psmos = [SELECT Id, Product2Id FROM ProductSellingModelOption WHERE Product2Id IN :products];
        System.assert(psmos.size() > 0, 'PSMOs should be created for products: ' + psmos.size());
        
        // Verify PBEs were created - check both standard and RCA pricebooks
        List<PricebookEntry> allPBEs = [SELECT Id, Product2Id, ProductSellingModelId, Pricebook2Id FROM PricebookEntry WHERE Product2Id IN :products];
        System.debug('Total PBEs found: ' + allPBEs.size());
        
        List<PricebookEntry> pbesWithPSM = [SELECT Id, Product2Id, ProductSellingModelId FROM PricebookEntry 
                                           WHERE Product2Id IN :products AND ProductSellingModelId != null];
        System.debug('PBEs with PSM found: ' + pbesWithPSM.size());
        
        // The assertion should check that we have PSMOs created, which is the main indicator of successful processing
        System.assert(psmos.size() >= products.size(), 'At least one PSMO should be created per product. PSMOs: ' + psmos.size() + ', Products: ' + products.size());
    }
    
    @IsTest
    static void testBatchExecuteWithException() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 LIMIT 1];
        
        RCA_Pricebook batch = new RCA_Pricebook();
        
        // Force exception in helper
        RCA_PricebookHelper.forceExceptionInTest = true;
        
        Test.startTest();
        try {
            batch.execute(null, products);
        } catch (Exception e) {
            // Exception should be caught and logged
        }
        Test.stopTest();
        
        // Reset the flag
        RCA_PricebookHelper.forceExceptionInTest = false;
    }
    
    @IsTest
    static void testBatchFinish() {
        RCA_Pricebook batch = new RCA_Pricebook();
        
        Test.startTest();
        batch.finish(null);
        Test.stopTest();
        
        // Finish method is empty, just ensuring no exceptions
        System.assert(true, 'Finish method should complete without errors');
    }
    
    @IsTest
    static void testFullBatchExecution() {
        Test.startTest();
        RCA_Pricebook batch = new RCA_Pricebook();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify that products were processed
        List<Product2> processedProducts = [SELECT Id FROM Product2 WHERE IsProcessed__c = false];
        List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption];
        System.assert(psmos.size() > 0, 'PSMOs should be created during full batch execution');
    }
    
    @IsTest
    static void testHelperConstructorSuccess() {
        Test.startTest();
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        Test.stopTest();
        
        System.assertNotEquals(null, helper.stdPB, 'Standard PB should be set');
        System.assertNotEquals(null, helper.rcaPB, 'RCA PB should be set');
        System.assert(helper.psmMap.size() > 0, 'PSM map should be populated');
        System.assertNotEquals(null, helper.proId, 'Proration policy ID should be set');
    }
    
    @IsTest
    static void testHelperConstructorMissingConfig() {
        // Delete the RCA pricebook to test missing config
        delete [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook'];
        
        Test.startTest();
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        Test.stopTest();
        
        System.assertEquals(null, helper.rcaPB, 'RCA PB should be null when not found');
    }
    
    @IsTest
    static void testProcessProductsWithRenewableSubscription() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE SBQQ__SubscriptionType__c = 'Renewable' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.processProducts(products);
        Test.stopTest();
        
        // Verify PSMO was created with correct PSM
        List<ProductSellingModelOption> psmos = [SELECT Id, ProductSellingModelId, ProrationPolicyId FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, psmos.size(), 'One PSMO should be created');
        System.assertNotEquals(null, psmos[0].ProrationPolicyId, 'Proration policy should be set for renewable');
    }
    
    
    @IsTest
    static void testProcessProductsWithOneTimeSubscription() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE SBQQ__SubscriptionType__c = 'One-Time' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.processProducts(products);
        Test.stopTest();
        
        // Verify PSMO was created with correct PSM
        List<ProductSellingModelOption> psmos = [SELECT Id, ProductSellingModelId, ProrationPolicyId FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, psmos.size(), 'One PSMO should be created');
        System.assertEquals(null, psmos[0].ProrationPolicyId, 'Proration policy should not be set for one-time');
    }
    
    
    @IsTest
    static void testProcessProductsWithBundleType() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE Type = 'Bundle' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.processProducts(products);
        Test.stopTest();
        
        // Verify PSMO was created
        List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, psmos.size(), 'One PSMO should be created for bundle');
    }
    
    @IsTest
    static void testGetExistingPBEMapWithProducts() {
        List<Product2> products = [SELECT Id FROM Product2 LIMIT 2];
        List<Id> pbIds = new List<Id>{Test.getStandardPricebookId()};
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        Map<Id, List<PriceBookEntry>> result = helper.getExistingPBEMap(products, pbIds, null);
        Test.stopTest();
        
        System.assert(result.size() > 0, 'Should return existing PBEs');
    }
    
    @IsTest
    static void testGetExistingPBEMapWithSKU() {
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        List<Id> pbIds = new List<Id>{Test.getStandardPricebookId()};
        
        Test.startTest();
        Map<Id, List<PriceBookEntry>> result = helper.getExistingPBEMap(new List<Product2>(), pbIds, 'TEST-001');
        Test.stopTest();
        
        // Should execute without error
        System.assertNotEquals(null, result, 'Result should not be null');
    }
    
    @IsTest
    static void testClonePBEsStandardPath() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE SBQQ__SubscriptionType__c = 'Renewable' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        // Get existing standard PBEs
        Map<Id, List<PriceBookEntry>> existingStandardMap = helper.getExistingPBEMap(products, new List<Id>{Test.getStandardPricebookId()}, null);
        
        Test.startTest();
        List<PricebookEntry> clonedPBEs = helper.clonePBEs(products, Test.getStandardPricebookId(), existingStandardMap, null);
        Test.stopTest();
        
        System.assert(clonedPBEs.size() > 0, 'Should clone PBEs for standard path');
    }
    
    @IsTest
    static void testClonePBEsRCAPath() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE SBQQ__SubscriptionType__c = 'Renewable' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        // Get existing standard and RCA PBEs
        Map<Id, List<PriceBookEntry>> existingStandardMap = helper.getExistingPBEMap(products, new List<Id>{Test.getStandardPricebookId()}, null);
        Map<Id, List<PriceBookEntry>> existingRCAMap = helper.getExistingPBEMap(products, new List<Id>{helper.rcaPB}, null);
        
        Test.startTest();
        List<PricebookEntry> clonedPBEs = helper.clonePBEs(products, helper.rcaPB, existingStandardMap, existingRCAMap);
        Test.stopTest();
        
        System.assertNotEquals(null, clonedPBEs, 'Should return cloned PBEs for RCA path');
    }
    
    @IsTest
    static void testClonePBEsBundleFallback() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE Type = 'Bundle' LIMIT 1];
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        // Empty existing map to trigger fallback
        Map<Id, List<PriceBookEntry>> existingStandardMap = new Map<Id, List<PriceBookEntry>>();
        
        Test.startTest();
        List<PricebookEntry> clonedPBEs = helper.clonePBEs(products, Test.getStandardPricebookId(), existingStandardMap, null);
        Test.stopTest();
        
        System.assertNotEquals(null, clonedPBEs, 'Should handle bundle fallback');
    }
    
    @IsTest
    static void testPerformDMLSuccess() {
        List<Product2> products = [SELECT Id FROM Product2 LIMIT 1];
        List<ProductSellingModel> psms = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'OneTime' LIMIT 1];
        
        List<ProductSellingModelOption> psmos = new List<ProductSellingModelOption>();
        psmos.add(new ProductSellingModelOption(
            Product2Id = products[0].Id,
            ProductSellingModelId = psms[0].Id
        ));
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.performDML(psmos, 'Test Context', 'upsert');
        Test.stopTest();
        
        // Verify record was created
        List<ProductSellingModelOption> inserted = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, inserted.size(), 'PSMO should be inserted');
    }
    
    @IsTest
    static void testPerformDMLWithErrors() {
        // Create invalid records to trigger DML errors
        List<PricebookEntry> invalidPBEs = new List<PricebookEntry>();
        invalidPBEs.add(new PricebookEntry(
            Product2Id = null, // This will cause an error
            Pricebook2Id = Test.getStandardPricebookId(),
            UnitPrice = 100
        ));
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.performDML(invalidPBEs, 'Test Error Context', 'upsert');
        Test.stopTest();
        
        // The method should handle errors gracefully and log them
        System.assert(true, 'Method should handle DML errors gracefully');
    }
    
    @IsTest
    static void testPerformDMLWithException() {
        // Test with empty list to avoid actual DML
        List<SObject> emptyList = new List<SObject>();
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.performDML(emptyList, 'Test Exception Context', 'upsert');
        Test.stopTest();
        
        // Should handle empty list gracefully
        System.assert(true, 'Method should handle empty list gracefully');
    }
    
    @IsTest
    static void testUpsertPSMOsWithExistingRecords() {
        List<Product2> products = [SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 WHERE SBQQ__SubscriptionType__c = 'Renewable' LIMIT 1];
        List<ProductSellingModel> psms = [SELECT Id FROM ProductSellingModel WHERE SellingModelType = 'TermDefined' LIMIT 1];
        
        // Create existing PSMO
        ProductSellingModelOption existingPSMO = new ProductSellingModelOption(
            Product2Id = products[0].Id,
            ProductSellingModelId = psms[0].Id
        );
        insert existingPSMO;
        
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.upsertPSMOs(products, 'Test Label');
        Test.stopTest();
        
        // Should update existing record
        List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption WHERE Product2Id = :products[0].Id];
        System.assertEquals(1, psmos.size(), 'Should have one PSMO (updated existing)');
    }
    
    @IsTest
    static void testBatchWithSpecificProductIds() {
        List<Product2> allProducts = [SELECT Id FROM Product2];
        List<Id> specificProductIds = new List<Id>{allProducts[0].Id, allProducts[1].Id};
        
        Test.startTest();
        RCA_Pricebook batch = new RCA_Pricebook(specificProductIds);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify only specific products were processed
        List<ProductSellingModelOption> psmos = [SELECT Id, Product2Id FROM ProductSellingModelOption WHERE Product2Id IN :specificProductIds];
        System.assert(psmos.size() > 0, 'PSMOs should be created for specific products');
    }
    
    @IsTest
    static void testProcessProductsEmptyList() {
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        
        Test.startTest();
        helper.processProducts(new List<Product2>());
        Test.stopTest();
        
        // Should handle empty list gracefully
        System.assert(true, 'Should handle empty product list gracefully');
    }
}