@isTest
public class RCA_PricebookBatchTest {

    @testSetup
    static void setupTestData() {
        // Create standard pricebook (though it exists by default)
        Pricebook2 standardPricebook = new Pricebook2(
            Id = Test.getStandardPricebookId(),
            IsActive = true
        );
        update standardPricebook;

        // Create RCA Pricebook
        Pricebook2 rcaPB = new Pricebook2(Name = 'RCA_PriceBook', IsActive = true);
        insert rcaPB;

        // Create Product Selling Model
        ProductSellingModel psm = new ProductSellingModel(Name = 'One Time', Status = 'Active');
        insert psm;

        // Create products
        List<Product2> prods = new List<Product2>{
            new Product2(Name = 'Prod A', StockKeepingUnit = 'SKU-A', IsActive = true),
            new Product2(Name = 'Prod B', StockKeepingUnit = 'SKU-B', IsActive = true),
            new Product2(Name = 'Bundle A', StockKeepingUnit = 'SKU-A - Bundle', IsActive = true, Type = 'Bundle'),
            new Product2(Name = 'Bundle B', StockKeepingUnit = 'SKU-B - Bundle', IsActive = true, Type = 'Bundle')
        };
        insert prods;

        // Create standard pricebook entries for non-bundle products
        List<PricebookEntry> stdPBEs = new List<PricebookEntry>();
        for (Product2 p : [SELECT Id FROM Product2 WHERE Type != 'Bundle']) {
            stdPBEs.add(new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = p.Id,
                UnitPrice = 100,
                IsActive = true
            ));
        }
        insert stdPBEs;
    }

    @isTest
    static void testProcessProducts() {
        List<Product2> testProducts = [SELECT Id, Name, StockKeepingUnit, Type FROM Product2];

        Test.startTest();
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        helper.processProducts(testProducts);
        Test.stopTest();

        // Verify PSMOs were created for all products
        List<ProductSellingModelOption> psmoList = [SELECT Id, Product2Id FROM ProductSellingModelOption];
        System.assertEquals(testProducts.size(), psmoList.size(), 'All products should have PSMOs');

        // Verify PBEs were created in standard pricebook
        List<PricebookEntry> stdPBEs = [
            SELECT Id FROM PricebookEntry 
            WHERE Pricebook2Id = :Test.getStandardPricebookId()
            AND Product2Id IN :testProducts
        ];
        Integer stdPbeCount = [SELECT COUNT() FROM PricebookEntry WHERE Pricebook2Id = :Test.getStandardPricebookId() AND IsActive = true];

        System.assert(stdPbeCount >= testProducts.size(), 'All products should have standard PBEs');

        // Verify PBEs were created in RCA pricebook for non-bundle products
        Pricebook2 rcaPB = [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        List<PricebookEntry> rcaPBEs = [
            SELECT Id FROM PricebookEntry 
            WHERE Pricebook2Id = :rcaPB.Id
            AND Product2Id IN :testProducts
        ];
        System.assertEquals(testProducts.size(), rcaPBEs.size(), 'Allproducts should have RCA PBEs');
    }

    @isTest
    static void testRCA_PricebookBatch() {
        List<Id> productIds = new List<Id>();
        for (Product2 p : [SELECT Id FROM Product2]) {
            productIds.add(p.Id);
        }

        Test.startTest();
        Database.executeBatch(new RCA_PricebookBatchVersion2(productIds), 200);
        Test.stopTest();

        // Verify PSMOs were created for all products
        Integer psmoCount = [SELECT COUNT() FROM ProductSellingModelOption];
        System.assertEquals(productIds.size(), psmoCount, 'Batch should have created PSMOs for all products');

        // Verify PBEs were created in both pricebooks
        Pricebook2 rcaPB = [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        Integer stdPbeCount = [SELECT COUNT() FROM PricebookEntry WHERE Pricebook2Id = :Test.getStandardPricebookId() AND IsActive = true];
        Integer rcaPbeCount = [SELECT COUNT() FROM PricebookEntry WHERE Pricebook2Id = :rcaPB.Id AND IsActive = true];
        
        System.assert(stdPbeCount > 0, 'Batch should have created standard PBEs');
        System.assert(rcaPbeCount > 0, 'Batch should have created RCA PBEs');
    }

    @isTest
    static void testDefaultConstructor() {
        // Test data setup
        List<Product2> testProducts = new List<Product2>{
            new Product2(Name = 'Test Product 1', StockKeepingUnit = 'SKU-001', IsActive = true),
            new Product2(Name = 'Test Product 2', StockKeepingUnit = 'SKU-002', IsActive = true)
        };
        insert testProducts;
    
        Test.startTest();
        // Instantiate using default constructor
        RCA_PricebookBatchVersion2 batch = new RCA_PricebookBatchVersion2();
        // Execute batch to verify it processes all products
        Id jobId = Database.executeBatch(batch);
        Test.stopTest();
    
        // Verify our specific batch job was created
        List<AsyncApexJob> jobs = [SELECT Id, Status, JobItemsProcessed, TotalJobItems 
                                 FROM AsyncApexJob 
                                 WHERE Id = :jobId];
        
        System.assertEquals(1, jobs.size(), 'Should have our test batch job');
        
    }

    @isTest
    static void testBatchWithInvalidBundle() {
        // Create intentionally broken bundle (missing SKU suffix match)
        Product2 brokenBundle = new Product2(
            Name = 'Invalid Bundle',
            StockKeepingUnit = 'UnknownBase - Bundle',
            IsActive = true,
            Type = 'Bundle'
        );
        insert brokenBundle;

        Test.startTest();
        Database.executeBatch(new RCA_PricebookBatchVersion2(new List<Id>{ brokenBundle.Id }), 1);
        Test.stopTest();

        // Assert that an error log was created
        List<Batch_Error_Log__c> errorLogs = [
            SELECT Id, Error_Message__c
            FROM Batch_Error_Log__c
            WHERE Batch_Class_Name__c = 'RCA_PricebookBatchVersion2'
            AND Method_Name__c = 'createBundlePBEs'
        ];
        System.assert(!errorLogs.isEmpty(), 'An error log should have been created for the invalid bundle');
        System.assert(errorLogs[0].Error_Message__c.contains('Missing base SKU or price for bundle'), 
                     'Expected error about missing base SKU');
    }
    
    @isTest
    static void testNegativeConfig() {
        // Delete required configuration
        delete [SELECT Id FROM Pricebook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        // delete [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time' LIMIT 1];
        
        List<Product2> testProducts = [SELECT Id, Name, StockKeepingUnit, Type FROM Product2];
        List<Id> pdIds = new List<Id>();
        for(Product2 pd: testProducts){
            pdIds.add(pd.Id);
        }

        Test.startTest();
        // RCA_PricebookHelper helper = new RCA_PricebookHelper();
        // helper.processProducts(testProducts);
        Database.executeBatch(new RCA_PricebookBatchVersion2(pdIds), 200);
        Test.stopTest();

        // Verify error was logged
        List<Batch_Error_Log__c> errorLogs = [
            SELECT Id, Error_Message__c 
            FROM Batch_Error_Log__c 
            WHERE Batch_Class_Name__c = 'RCA_PricebookBatchVersion2'
            AND Method_Name__c = 'processProducts'
        ];
        System.assert(!errorLogs.isEmpty(), 'Expected an error log');
        System.assert(errorLogs[0].Error_Message__c.contains('Missing config values'), 
                     'Expected error about missing config');
        
        // Verify no PSMOs or PBEs were created
        System.assertEquals(0, [SELECT COUNT() FROM ProductSellingModelOption], 'No PSMOs should be created with missing config');
        System.assertEquals(2, [SELECT COUNT() FROM PricebookEntry WHERE IsActive = true], 'Only the original 2 PBEs should exist');
    }

    @isTest
    static void testUpsertPSMOs() {
        List<Product2> products = [SELECT Id FROM Product2];
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel LIMIT 1];
        
        Test.startTest();
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        Map<Id, Id> result = helper.upsertPSMOs(products, psm.Id, 'Test');
        Test.stopTest();
        
        // Verify PSMOs were created
        System.assertEquals(products.size(), result.size(), 'All products should have PSMO mappings');
        System.assertEquals(products.size(), [SELECT COUNT() FROM ProductSellingModelOption], 'PSMOs should be created');
        
        // Test update scenario
        Map<Id, Id> updateResult = helper.upsertPSMOs(products, psm.Id, 'Test Update');
        System.assertEquals(products.size(), updateResult.size(), 'All products should still have PSMO mappings');
    }

    @isTest
    static void testCreateBundlePBEs() {
        // Create products
        Product2 baseProduct = new Product2(
            Name = 'Prod C', 
            StockKeepingUnit = 'SKU-C', 
            IsActive = true
        );
        Product2 bundle = new Product2(
            Name = 'Bundle C', 
            StockKeepingUnit = 'SKU-C - Bundle', 
            IsActive = true, 
            Type = 'Bundle'
        );
        insert new List<Product2>{baseProduct, bundle};

        // Create standard pricebook entry for base product
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = baseProduct.Id,
            UnitPrice = 120,
            IsActive = true
        );
        insert pbe;

        // Get Product Selling Model (created in testSetup)
        ProductSellingModel psm = [SELECT Id FROM ProductSellingModel LIMIT 1];
        
        // Create SKU map and price map
        Map<String, Id> skuMap = new Map<String, Id>{
            'SKU-C' => baseProduct.Id,
            'SKU-C - Bundle' => bundle.Id
        };
        Map<Id, Decimal> priceMap = new Map<Id, Decimal>{
            baseProduct.Id => 120 // Using 120 to match the PBE we created
        };
        
        Test.startTest();
        RCA_PricebookHelper helper = new RCA_PricebookHelper();
        List<PricebookEntry> result = helper.createBundlePBEs(
            new List<Product2>{bundle},
            Test.getStandardPricebookId(), // Using standard pricebook ID
            psm.Id,
            skuMap,
            priceMap,
            new Map<String, Id>()
        );
        Test.stopTest();
        
        // Verify results
        System.assertEquals(1, result.size(), 'Should create one bundle PBE');
        System.assertEquals(120, result[0].UnitPrice, 'Bundle price should match base product');
    }

    @isTest
    static void testExecuteBlockWithBadProduct() {
        // Insert a dummy product
        Product2 p = new Product2(
            Name = 'Thrower Product',
            StockKeepingUnit = 'SKU-THROW',
            IsActive = true
        );
        insert p;

        // Enable simulated exception in helper
        RCA_PricebookHelper.forceExceptionInTest = true;

        Test.startTest();
        Database.executeBatch(new RCA_PricebookBatchVersion2(new List<Id>{ p.Id }), 1);
        Test.stopTest();

        List<Batch_Error_Log__c> logs = [
            SELECT Id FROM Batch_Error_Log__c
            WHERE Batch_Class_Name__c = 'RCA_PricebookBatchVersion2'
            AND Method_Name__c = 'execute'
        ];
        System.assert(!logs.isEmpty(), 'Expected an error log for exception in execute');
    }


}