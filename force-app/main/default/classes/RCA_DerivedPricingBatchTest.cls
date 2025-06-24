@isTest
private class RCA_DerivedPricingBatchTest {
    
    @testSetup
    static void testDatasetup() {
        Id standardPBId = Test.getStandardPricebookId();
        
        // Insert test products
        List<Product2> testProducts = new List<Product2>();
        
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
        
        Product2 product2 = new Product2(
            Name = 'Test Product List',
            IsActive = true,
            StockKeepingUnit = 'TP-LIST-01',
            ProductCode = 'TP-LIST-01',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'List',
            SBQQ__SubscriptionPercent__c = 15.00
        );
        testProducts.add(product2);
        
        Product2 product3 = new Product2(
            Name = 'Test Product Invalid',
            IsActive = true,
            StockKeepingUnit = 'TP-INVALID-01',
            ProductCode = 'TP-INVALID-01',
            SBQQ__PricingMethod__c = 'Percent Of Total'
        );
        testProducts.add(product3);
        
        insert testProducts;
        
        product2.SBQQ__SubscriptionTarget__c = product1.Id;
        update product2;
        
        Pricebook2 pricebook = new Pricebook2(Name = 'RCA_PriceBook', IsActive = true);
        insert pricebook;
        
        ProductSellingModel psm = new ProductSellingModel(Name = 'One Time', SellingModelType = 'OneTime', Status = 'Active');
        insert psm;
        
        List<ProductSellingModelOption> psmoList = new List<ProductSellingModelOption>{
            new ProductSellingModelOption(Product2Id = product1.Id, ProductSellingModelId = psm.Id),
                new ProductSellingModelOption(Product2Id = product2.Id, ProductSellingModelId = psm.Id)
                };
                    insert psmoList;
        
        List<PricebookEntry> pbes = new List<PricebookEntry>{
            new PricebookEntry(Product2Id = product1.Id, Pricebook2Id = standardPBId, ProductSellingModelId = psm.Id, UnitPrice = 100.00, IsActive = true),
                new PricebookEntry(Product2Id = product1.Id, Pricebook2Id = pricebook.Id, ProductSellingModelId = psm.Id, UnitPrice = 0, IsActive = true, IsDerived = true)
                };
                    insert pbes;
    }
    
    @isTest
    static void testBatchWithAllProducts() {
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();
        
        // Verify results for product1 (Net)
        Product2 productNet = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'TP-NET-01'];
        List<PricebookEntry> pbesNet = [SELECT Id, IsDerived, UnitPrice FROM PricebookEntry 
                                        WHERE Product2Id = :productNet.Id AND Pricebook2.Name = 'RCA_PriceBook'];
        System.assertEquals(1, pbesNet.size(), 'Should have RCA PBE');
        System.assertEquals(true, pbesNet[0].IsDerived, 'Should be derived');
        
        // Verify derived price was created
        List<PriceBookEntryDerivedPrice> derivedPrices = [SELECT Id FROM PriceBookEntryDerivedPrice 
                                                          WHERE PricebookEntryId = :pbesNet[0].Id];
        System.assert(!derivedPrices.isEmpty(), 'Derived price should exist');
    }

    @isTest
    static void productwithNoPricebookEntries() {
        Id standardPBId = Test.getStandardPricebookId();

        Product2 product = new Product2();
        product.Name ='Derived Test Product';
        product.StockKeepingUnit = 'DTP-001';
        product.ProductCode = 'DTP-001';
        product.IsActive = True;
        product.SBQQ__PricingMethod__c='Percent Of Total';
        product.SBQQ__SubscriptionBase__c='Net';
        product.SBQQ__SubscriptionPercent__c = 20.00;
        insert product;

        Test.startTest();
        List<Id> productid = new List<Id>{product.Id};
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(productid);
        Database.executeBatch(batch,200);
        Test.stopTest();

        ProductSellingModelOption psmo = [
            SELECT Product2Id, ProductSellingModelId 
            FROM ProductSellingModelOption 
            WHERE Product2Id = :product.Id
        ];
        System.assertEquals(product.Id, psmo.Product2Id, 'PSMO not created');

        List<PricebookEntry> stdPBEs = [
            SELECT UnitPrice, IsDerived 
            FROM PricebookEntry 
            WHERE Product2Id = :product.Id AND Pricebook2Id = :standardPBId
        ];
        System.assertEquals(1, stdPBEs.size(), 'Standard Pricebook entry should have been created');
        System.assertEquals(0, stdPBEs[0].UnitPrice, 'Expected UnitPrice = 0');

        Pricebook2 rcaPB = [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];

        List<PricebookEntry> rcaPBEs = [
            SELECT Id, UnitPrice, IsDerived 
            FROM PricebookEntry 
            WHERE Product2Id = :product.Id AND Pricebook2Id = :rcaPB.Id
        ];
        System.assertEquals(1, rcaPBEs.size(), 'RCA Pricebook entry should be created');
        System.assertEquals(true, rcaPBEs[0].IsDerived, 'RCA PBE should be marked as derived');

        List<PriceBookEntryDerivedPrice> derivedPrices = [
            SELECT Id 
            FROM PriceBookEntryDerivedPrice 
            WHERE PricebookEntryId = :rcaPBEs[0].Id
        ];
        System.assertEquals(1, derivedPrices.size(), 'Derived Price should be created');
    }

    
    
    @isTest
    static void productwithExistingpbe() {
        Id standardPBId = Test.getStandardPricebookId();
        
        Product2 product = new Product2(
            Name = 'Product with no psmo',
            IsActive = true,
            StockKeepingUnit = 'PWNP-001',
            ProductCode = 'PWNP-001',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 10.00
        );
        insert product;
        
        Pricebook2 pb = [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time'];
        
        insert new ProductSellingModelOption(Product2Id = product.Id, ProductSellingModelId = psm.Id);
        
        insert new PricebookEntry(
            Product2Id = product.Id,
            Pricebook2Id = standardPBId,
            ProductSellingModelId = psm.Id,
            UnitPrice = 0,
            IsDerived = True,
            IsActive = true
        );
        
        Test.startTest();
        Database.executeBatch(new RCA_DerivedPricingBatch(new List<Id>{ product.Id }), 200);
        Test.stopTest();
        
        List<PricebookEntry> result = [
            SELECT Id, IsDerived 
            FROM PricebookEntry 
            WHERE Product2Id = :product.Id AND Pricebook2.Name = 'RCA_PriceBook'
        ];
        System.assertEquals(1, result.size());
        System.assertEquals(true, result[0].IsDerived);
    }
    
    @isTest
    static void testErrorHandling() {
        RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper(new List<String>());
        Test.startTest();
        helper.processProducts(new List<Product2>{
            new Product2(
                Name = 'Invalid Product',
                SBQQ__PricingMethod__c = 'Percent Of Total'
            )
                });
        Test.stopTest();
        
        System.assert(!helper.errorMessages.isEmpty(), 'Should have recorded errors');
    }
    
    @isTest
    static void testMissingStandardPricebook() {
        Product2 product = new Product2(
            Name = 'Missing Standard PBE Product',
            IsActive = true,
            StockKeepingUnit = 'MISSING-STANDARD',
            ProductCode = 'MISSING-STANDARD',
            SBQQ__PricingMethod__c = 'Percent Of Total',
            SBQQ__SubscriptionBase__c = 'Net',
            SBQQ__SubscriptionPercent__c = 20
        );
        insert product;
        
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time'];
        insert new ProductSellingModelOption(Product2Id = product.Id, ProductSellingModelId = psm.Id);
        
        Test.startTest();
        Database.executeBatch(new RCA_DerivedPricingBatch(new List<Id>{ product.Id }), 200);
        Test.stopTest();
        
        List<PricebookEntry> pbEntries = [
            SELECT Id FROM PricebookEntry 
            WHERE Product2Id = :product.Id AND Pricebook2.Name = 'RCA_PriceBook'
        ];
        System.assertEquals(0, pbEntries.size(), 'No RCA_PBE should be created without standard PBE');
    }
}