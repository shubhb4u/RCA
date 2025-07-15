@isTest
private class RCA_DerivedPricingBatchTest {
    
    @testSetup
    static void testDatasetup() {
        Id standardPBId = Test.getStandardPricebookId();
        
        // Insert test products with various scenarios
        List<Product2> testProducts = new List<Product2>();
        
        // Product 1: Net-based subscription
        Product2 product1 = new Product2(
            Name = 'Test Product Net',
            IsActive = true,
            StockKeepingUnit = 'TP-NET-01',
            ProductCode = 'TP-NET-01',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 10.00
        );
        testProducts.add(product1);
        
        // Product 2: List-based subscription (will be target)
        Product2 product2 = new Product2(
            Name = 'Test Product Target',
            IsActive = true,
            StockKeepingUnit = 'TP-TARGET-01',
            ProductCode = 'TP-TARGET-01',
            SBQQ__PricingMethod__c = 'List',
            SBQQ__SubscriptionBase__c = 'List',
            SBQQ__SubscriptionPercent__c = 0
        );
        testProducts.add(product2);
        
        // Product 3: List-based subscription (references product2)
        Product2 product3 = new Product2(
            Name = 'Test Product List',
            IsActive = true,
            StockKeepingUnit = 'TP-LIST-01',
            ProductCode = 'TP-LIST-01',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'List',
            SBQQ__SubscriptionPercent__c = 15.00
        );
        testProducts.add(product3);
        
        // Product 4: Invalid - missing required fields
        Product2 product4 = new Product2(
            Name = 'Test Product Invalid',
            IsActive = true,
            StockKeepingUnit = 'TP-INVALID-01',
            ProductCode = 'TP-INVALID-01',
            SBQQ__PricingMethod__c = 'Percent Of Total'
            // Missing SBQQ__SubscriptionBase__c and SBQQ__SubscriptionPercent__c
        );
        testProducts.add(product4);
        
        // Product 5: For testing existing RCA PBE scenarios
        Product2 product5 = new Product2(
            Name = 'Test Product Existing RCA',
            IsActive = true,
            StockKeepingUnit = 'TP-RCA-01',
            ProductCode = 'TP-RCA-01',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 25.00
        );
        testProducts.add(product5);
        
        insert testProducts;
        
        // Set up subscription target relationship
        product3.SBQQ__SubscriptionTarget__c = product2.Id;
        update product3;
        
        // Create RCA Pricebook
        Pricebook2 pricebook = new Pricebook2(Name = 'RCA_PriceBook', IsActive = true);
        insert pricebook;
        
        // Create ProductSellingModel
        ProductSellingModel psm = new ProductSellingModel(
            Name = 'One Time', 
            SellingModelType = 'OneTime', 
            Status = 'Active'
        );
        insert psm;
        
        // Create ProductSellingModelOptions
        List<ProductSellingModelOption> psmoList = new List<ProductSellingModelOption>();
        for (Product2 prod : testProducts) {
            psmoList.add(new ProductSellingModelOption(
                Product2Id = prod.Id, 
                ProductSellingModelId = psm.Id
            ));
        }
        insert psmoList;
        
        // Create various PricebookEntry scenarios
        List<PricebookEntry> pbes = new List<PricebookEntry>();
        
        // Standard PBEs for products 1, 2, 3
        pbes.add(new PricebookEntry(
            Product2Id = product1.Id, 
            Pricebook2Id = standardPBId, 
            ProductSellingModelId = psm.Id, 
            UnitPrice = 100.00, 
            IsActive = true
        ));
        
        pbes.add(new PricebookEntry(
            Product2Id = product2.Id, 
            Pricebook2Id = standardPBId, 
            ProductSellingModelId = psm.Id, 
            UnitPrice = 200.00, 
            IsActive = true
        ));
        
        // Product 3 - Standard PBE with derived = true, price = 0 (perfect match scenario)
        pbes.add(new PricebookEntry(
            Product2Id = product3.Id, 
            Pricebook2Id = standardPBId, 
            ProductSellingModelId = psm.Id, 
            UnitPrice = 0, 
            IsActive = true,
            IsDerived = true
        ));
        
        // Product 5 - Standard PBE
        pbes.add(new PricebookEntry(
            Product2Id = product5.Id, 
            Pricebook2Id = standardPBId, 
            ProductSellingModelId = psm.Id, 
            UnitPrice = 150.00, 
            IsActive = true
        ));
        
        // Product 5 - RCA PBE (existing scenario)
        pbes.add(new PricebookEntry(
            Product2Id = product5.Id, 
            Pricebook2Id = pricebook.Id, 
            ProductSellingModelId = psm.Id, 
            UnitPrice = 0, 
            IsActive = true,
            IsDerived = true
        ));
        
        insert pbes;
    }
    
    @isTest
    static void testBatchWithAllProducts() {
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify results for Net-based product
        Product2 productNet = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-NET-01'];
        List<PricebookEntry> pbesNet = [SELECT Id, IsDerived, UnitPrice FROM PricebookEntry 
                                        WHERE Product2Id = :productNet.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, pbesNet.size(), 'Should have RCA PBE for Net product');
        System.assertEquals(true, pbesNet[0].IsDerived, 'Should be derived');
        
        // Verify derived price was created
        List<PriceBookEntryDerivedPrice> derivedPrices = [SELECT Id, Formula, PricingSource FROM PriceBookEntryDerivedPrice 
                                                          WHERE PricebookEntryId = :pbesNet[0].Id];
        System.assertEquals(1, derivedPrices.size(), 'Derived price should exist for Net product');
        System.assertEquals('Header', derivedPrices[0].PricingSource, 'Should use Header source for Net');
        System.assert(derivedPrices[0].Formula.contains('HeaderTotal'), 'Formula should contain HeaderTotal');
    }
    
    @isTest
    static void testListBasedProductWithTarget() {
        Test.startTest();
        Product2 productList = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-LIST-01'];
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{productList.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify RCA PBE was created for List-based product
        List<PricebookEntry> pbesList = [SELECT Id, IsDerived FROM PricebookEntry 
                                         WHERE Product2Id = :productList.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, pbesList.size(), 'Should have RCA PBE for List product');
        
        // Verify derived price with Product source
        List<PriceBookEntryDerivedPrice> derivedPrices = [SELECT Id, Formula, PricingSource, ContributingProductId 
                                                          FROM PriceBookEntryDerivedPrice 
                                                          WHERE PricebookEntryId = :pbesList[0].Id];
        System.assertEquals(1, derivedPrices.size(), 'Derived price should exist for List product');
        System.assertEquals('Product', derivedPrices[0].PricingSource, 'Should use Product source for List');
        System.assert(derivedPrices[0].Formula.contains('ListPrice'), 'Formula should contain ListPrice');
        System.assertNotEquals(null, derivedPrices[0].ContributingProductId, 'Should have contributing product');
        
        // Verify source product PBE was created in RCA pricebook
        Product2 targetProduct = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-TARGET-01'];
        List<PricebookEntry> sourcePbes = [SELECT Id FROM PricebookEntry 
                                           WHERE Product2Id = :targetProduct.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, sourcePbes.size(), 'Source product should have RCA PBE');
    }
    
    @isTest
    static void testProductWithExistingStandardPBEPerfectMatch() {
        Test.startTest();
        Product2 product = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-LIST-01'];
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{product.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should create RCA PBE based on perfect match from standard
        List<PricebookEntry> rcaPbes = [SELECT Id, IsDerived FROM PricebookEntry 
                                        WHERE Product2Id = :product.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, rcaPbes.size(), 'Should create RCA PBE from perfect match');
        System.assertEquals(true, rcaPbes[0].IsDerived, 'RCA PBE should be derived');
    }
    
    @isTest
    static void testProductWithExistingRCAPBE() {
        Test.startTest();
        Product2 product = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-RCA-01'];
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{product.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should use existing RCA PBE
        List<PricebookEntry> rcaPbes = [SELECT Id, IsDerived FROM PricebookEntry 
                                        WHERE Product2Id = :product.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, rcaPbes.size(), 'Should use existing RCA PBE');
        
        // Should create derived price for existing PBE
        List<PriceBookEntryDerivedPrice> derivedPrices = [SELECT Id FROM PriceBookEntryDerivedPrice 
                                                          WHERE PricebookEntryId = :rcaPbes[0].Id];
        System.assertEquals(1, derivedPrices.size(), 'Should create derived price for existing PBE');
    }
    
    @isTest
    static void testProductWithNoPricebookEntries() {
        // Create a product with no existing PBEs
        Product2 product = new Product2(
            Name = 'No PBE Product',
            IsActive = true,
            StockKeepingUnit = 'NO-PBE-001',
            ProductCode = 'NO-PBE-001',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 20.00
        );
        insert product;
        
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{product.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        Id standardPBId = Test.getStandardPricebookId();
        
        // Should create both standard and RCA PBEs
        List<PricebookEntry> standardPbes = [SELECT Id, IsDerived FROM PricebookEntry 
                                             WHERE Product2Id = :product.Id AND Pricebook2Id = :standardPBId];
        System.assertEquals(1, standardPbes.size(), 'Should create standard PBE');
        
        List<PricebookEntry> rcaPbes = [SELECT Id, IsDerived FROM PricebookEntry 
                                        WHERE Product2Id = :product.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, rcaPbes.size(), 'Should create RCA PBE');
        
        // Should create PSMO
        List<ProductSellingModelOption> psmos = [SELECT Id FROM ProductSellingModelOption 
                                                 WHERE Product2Id = :product.Id];
        System.assertEquals(1, psmos.size(), 'Should create PSMO');
    }
    
    @isTest
    static void testErrorHandlingInvalidProduct() {
        // Test with product missing required fields
        Product2 invalidProduct = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-INVALID-01'];
        
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{invalidProduct.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should not create any PBEs for invalid product
        List<PricebookEntry> pbes = [SELECT Id FROM PricebookEntry WHERE Product2Id = :invalidProduct.Id];
        System.assertEquals(0, pbes.size(), 'Should not create PBEs for invalid product');
    }
    
    @isTest
    static void testHelperErrorHandling() {
        List<String> errorMessages = new List<String>();
        RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper(errorMessages);
        
        // Test with invalid product data
        Product2 invalidProduct = new Product2(
            Name = 'Invalid Product',
            SBQQ__PricingMethod__c = 'Percent Of Total'
            // Missing required fields
        );
        
        Test.startTest();
        helper.processProducts(new List<Product2>{invalidProduct});
        Test.stopTest();
        
        System.assert(!errorMessages.isEmpty(), 'Should have recorded errors for invalid product');
    }
    
    @isTest
    static void testHelperWithNullSubscriptionData() {
        List<String> errorMessages = new List<String>();
        RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper(errorMessages);
        
        // Create product with missing subscription data
        Product2 product = new Product2(
            Name = 'Missing Subscription Data',
            IsActive = true,
            StockKeepingUnit = 'MSD-001',
            ProductCode = 'MSD-001',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net'
            // Missing SBQQ__SubscriptionPercent__c
        );
        insert product;
        
        Test.startTest();
        helper.processProducts(new List<Product2>{product});
        Test.stopTest();
        
        System.assert(!errorMessages.isEmpty(), 'Should record error for missing subscription data');
    }
    
    @isTest
    static void testHelperInitializationError() {
        // Test helper initialization with potential database issues
        List<String> errorMessages = new List<String>();
        
        Test.startTest();
        RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper(errorMessages);
        Test.stopTest();
        
        // Helper should initialize successfully in test context
        System.assertNotEquals(null, helper, 'Helper should be initialized');
    }
    
    @isTest
    static void testDerivedPriceCreationWithExistingPrices() {
        // Create a product and PBE first
        Product2 product = new Product2(
            Name = 'Existing Derived Price Product',
            IsActive = true,
            StockKeepingUnit = 'EDP-001',
            ProductCode = 'EDP-001',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 30.00
        );
        insert product;
        
        Pricebook2 rcaPB = [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time' LIMIT 1];
        
        PricebookEntry pbe = new PricebookEntry(
            Product2Id = product.Id,
            Pricebook2Id = rcaPB.Id,
            ProductSellingModelId = psm.Id,
            UnitPrice = 0,
            IsActive = true,
            IsDerived = true
        );
        insert pbe;
        
        // Create existing derived price
        PriceBookEntryDerivedPrice existingDP = new PriceBookEntryDerivedPrice(
            PricebookEntryId = pbe.Id,
            PricebookId = rcaPB.Id,
            DerivedPricingScope = 'Transactional',
            PricingSource = 'Header',
            Formula = 'HeaderTotal * 0.30',
            EffectiveFrom = Date.today()
        );
        insert existingDP;
        
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{product.Id});
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Should not create duplicate derived price
        List<PriceBookEntryDerivedPrice> derivedPrices = [SELECT Id FROM PriceBookEntryDerivedPrice 
                                                          WHERE PricebookEntryId = :pbe.Id];
        System.assertEquals(1, derivedPrices.size(), 'Should not create duplicate derived price');
    }
    
    @isTest
    static void testBatchWithSpecificProductIds() {
        List<Product2> products = [SELECT Id FROM Product2 WHERE StockKeepingUnit IN ('TP-NET-01', 'TP-LIST-01')];
        List<Id> productIds = new List<Id>();
        for (Product2 p : products) {
            productIds.add(p.Id);
        }
        
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(productIds);
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify processing for specific products
        List<PricebookEntry> rcaPbes = [SELECT Id FROM PricebookEntry 
                                        WHERE Product2Id IN :productIds AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assert(rcaPbes.size() >= 2, 'Should process specified products');
    }
    
    @isTest
    static void testPSMOCreationFailure() {
        // Test PSMO creation when ProductSellingModel doesn't exist
        List<String> errorMessages = new List<String>();
        RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper(errorMessages);
        
        // Delete the ProductSellingModel to force error
        delete [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time'];
        
        Product2 product = new Product2(
            Name = 'PSMO Error Product',
            IsActive = true,
            StockKeepingUnit = 'PSMO-ERROR-001',
            ProductCode = 'PSMO-ERROR-001',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 10.00
        );
        insert product;
        
        Test.startTest();
        helper.processProducts(new List<Product2>{product});
        Test.stopTest();
        
        System.assert(!errorMessages.isEmpty(), 'Should record PSMO creation error');
    }
}