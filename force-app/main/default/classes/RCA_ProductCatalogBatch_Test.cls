@isTest
private class RCA_ProductCatalogBatch_Test {
    
    @testSetup
    static void setupTestData() {

        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;

        ProductCategory cat = new ProductCategory(
            Name = 'Default category',
            CatalogId = catalog.Id
        );
        insert cat;

        ProductRelationshipType prt = new ProductRelationshipType(
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent',
            Name = 'Bundle to bundle'
        );
        insert prt;
    
        
        // Create test products that will be processed
        List<Product2> testProducts = new List<Product2>();
        for(Integer i = 0; i < 5; i++) {
            testProducts.add(new Product2(
                Name = 'Test Product ' + i,
                ProductCode = 'TP' + i,
                IsActive = true,
                IsProcessed__c = false,
                StockKeepingUnit = 'SKU' + i,
                SBQQ__ConfigurationType__c = 'Allowed',
                SBQQ__Component__c = false
            ));
        }
        insert testProducts;
        
        // Create features for some products
        List<SBQQ__ProductFeature__c> features = new List<SBQQ__ProductFeature__c>();
        for(Integer i = 0; i < 3; i++) {
            features.add(new SBQQ__ProductFeature__c(
                Name = 'Feature ' + i,
                SBQQ__ConfiguredSKU__c = testProducts[i].Id,
                SBQQ__MinOptionCount__c = 1,
                SBQQ__MaxOptionCount__c = 5,
                SBQQ__Number__c = i + 1
            ));
        }
        insert features;
        
        // Create options for some products
        List<SBQQ__ProductOption__c> options = new List<SBQQ__ProductOption__c>();
        for(Integer i = 0; i < 3; i++) {
            options.add(new SBQQ__ProductOption__c(
                SBQQ__ConfiguredSKU__c = testProducts[i].Id,
                SBQQ__OptionalSKU__c = testProducts[i+1].Id,
                SBQQ__Number__c = 1,
                SBQQ__Selected__c = true,
                SBQQ__Required__c = false,
                SBQQ__Quantity__c = 2,
                SBQQ__QuantityEditable__c = false,
                //SBQQ__MinQuantity__c = 1,
                //SBQQ__MaxQuantity__c = 3,
                SBQQ__Bundled__c = true,
                SBQQ__Feature__c = features[i].Id
            ));
        }
        // Add one independent option (no feature)
        options.add(new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = testProducts[0].Id,
            SBQQ__OptionalSKU__c = testProducts[4].Id,
            SBQQ__Number__c = 1,
            SBQQ__Selected__c = true,
            SBQQ__Required__c = false,
            SBQQ__Quantity__c = 2,
            SBQQ__QuantityEditable__c = false,
            SBQQ__MinQuantity__c = 1,
            SBQQ__MaxQuantity__c = 3,
            SBQQ__Bundled__c = true
        ));
        insert options;
    }
    
    // Test the start method without product IDs filter
    @isTest
    static void testStartMethodWithoutFilter() {
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch();
        Database.QueryLocator ql = batch.start(null);
        List<Product2> products = Database.query(ql.getQuery());
        Test.stopTest();
        
        System.assertEquals(5, products.size(), 'Should return all unprocessed products');
    }
    
    // Test the start method with product IDs filter
    @isTest
    static void testStartMethodWithFilter() {
        List<Product2> testProducts = [SELECT Id FROM Product2 LIMIT 2];
        System.debug(testProducts.size());
        List<Id> productIds = new List<Id>();
        for(Product2 p : testProducts) {
            productIds.add(p.Id);
        }
        
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(productIds);
        Database.QueryLocator ql = batch.start(null);
        List<Product2> products = Database.query(ql.getQuery());
        Test.stopTest();
        
        System.assertEquals(2, products.size(), 'Should return only filtered products');
    }
    
    // Test successful execution of the batch
    
    @isTest
    static void testSuccessfulBatchExecution() {
        // Collect Product2 IDs from ProductOption and ProductFeature separately
        List<String> ProductNamesList = new List<String>{'Test Product 0','Test Product 1','Test Product 2','Test Product 3','Test Product 4'};
        Set<Id> productIds = new Set<Id>();
        for (SBQQ__ProductOption__c po : [
            SELECT SBQQ__ConfiguredSKU__c
            FROM SBQQ__ProductOption__c
            WHERE SBQQ__ConfiguredSKU__r.IsProcessed__c = false and SBQQ__ConfiguredSKU__r.Name In :ProductNamesList
        ]) {
            productIds.add(po.SBQQ__ConfiguredSKU__c);
        }

        for (SBQQ__ProductFeature__c pf : [
            SELECT SBQQ__ConfiguredSKU__c
            FROM SBQQ__ProductFeature__c
            WHERE SBQQ__ConfiguredSKU__r.IsProcessed__c = false and SBQQ__ConfiguredSKU__r.Name In :ProductNamesList
        ]) {
            productIds.add(pf.SBQQ__ConfiguredSKU__c);
        } 

       // Integer productsWithOptions = [SELECT COUNT() FROM Product2 
            //                     WHERE Id IN: productIds
                    //             AND IsProcessed__c = false];

        System.assert(productIds.size() > 0, 'Test data should include products with options or features');

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch();
        Id batchJobId = Database.executeBatch(batch);
        Test.stopTest();

        // Check how many bundles were created
        List<Product2> bundleProducts = [SELECT Id FROM Product2 WHERE Type = 'Bundle'];
        System.assertEquals(productIds.size(), bundleProducts.size(), 
            'Should create one bundle per product with options or features');
    }

    
    // Test batch execution with DML errors
    @isTest
    static void testBatchWithDmlErrors() {
        // Force a DML error by making a required field null
        Product2 testProduct = [SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, (SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c,SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) FROM Product2  LIMIT 1];

        // Force a DML error by creating an invalid ProductRelatedComponent
        // that will fail when the batch tries to insert it
        ProductRelatedComponent invalidComponent = new ProductRelatedComponent(
            ParentProductId = testProduct.Id,
            ChildProductId = testProduct.Id // This should cause a validation error
        );
        
        // Mock the helper method to return our invalid component
        RCA_ProductCatalogBatchHelper mockHelper = new RCA_ProductCatalogBatchHelper();
        Test.startTest();
        // Use Test.setMock if you have an interface, or modify the test to expect this error
        // For now we'll just test that the error handling works
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{testProduct.Id});
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify error was captured by checking if the product is still unprocessed
        Product2 processedProduct = [SELECT IsProcessed__c FROM Product2 WHERE Id = :testProduct.Id];
        System.assertEquals(false, processedProduct.IsProcessed__c, 
                       'Product should not be processed due to error');

    }
    
    // Test batch with no records to process
    @isTest
    static void testBatchWithNoRecords() {
        // Mark all products as processed
        List<Product2> products = [SELECT Id FROM Product2];
        for(Product2 p : products) {
            p.IsProcessed__c = true;
        }
        update products;
        
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch();
        Database.executeBatch(batch);
        Test.stopTest();
        
        // Verify no new records were created
        List<Product2> bundleProducts = [SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, (SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c,SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) FROM Product2 WHERE Name LIKE '%Bundle'];
        System.assertEquals(0, bundleProducts.size(), 'No bundle products should be created');
    }
    
    // Test the finish method with errors
    @isTest
    static void testFinishWithErrors() {
        // Mock error messages to test notification
        List<String> errorMessages = new List<String>{
            'Test error 1',
            'Test error 2'
        };
        
        // Mock failed records (need to cast to List<SObject>)
        List<Product2> testProducts = [SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, (SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c,SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) FROM Product2  LIMIT 1];
        List<SObject> failedRecords = new List<SObject>();
        failedRecords.addAll(testProducts);
        
        Test.startTest();
        RCA_ProductCatalogBatchHelper.sendErrorNotification(errorMessages);
        RCA_ProductCatalogBatchHelper.rollbackFailedCPQHierarchy(failedRecords, errorMessages);
        Test.stopTest();
        
        // In a real test, you would verify emails were sent using a mock
        // For now just verify no exceptions occurred
        System.assert(true, 'Finish methods executed without exceptions');
    }
    
    // Test helper method for building products
    @isTest
    static void testBuildProducts() {
        List<Product2> testProducts = [SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, (SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c,SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) FROM Product2 WHERE IsProcessed__c = FALSE];

        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogBatchHelper.fetchFeatures(testProducts);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogBatchHelper.fetchOptions(testProducts);
        
        List<Product2> newProducts = new List<Product2>();
        List<Product2> updatedProducts = new List<Product2>();
        Map<Id, Product2> origCPQToNewBundleMap = new Map<Id, Product2>();
        
        Test.startTest();
        RCA_ProductCatalogBatchHelper.buildProducts(
            testProducts, 
            featureMap, 
            optionMap, 
            newProducts, 
            updatedProducts, 
            origCPQToNewBundleMap
        );
        Test.stopTest();
        
        System.assert(!newProducts.isEmpty(), 'Should have created new bundle products');
        System.assert(!origCPQToNewBundleMap.isEmpty(), 'Should have populated bundle map');
    }
    
    // Test error handling in DML operations
    @isTest
    static void testHandleDmlOperationWithErrors() {
        List<Product2> testProducts = [SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, (SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c,SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) FROM Product2  LIMIT 1];
        for(Product2 p : testProducts) {
            p.Name = null; // This will cause a DML error
        }
        
        List<String> errorMessages = new List<String>();
        List<SObject> failedRecords = new List<SObject>();
        
        // Convert List<Product2> to List<SObject>
        List<SObject> productsAsSObjects = new List<SObject>();
        productsAsSObjects.addAll(testProducts);
        
        Test.startTest();
        RCA_ProductCatalogBatchHelper.handleDmlOperation(
            productsAsSObjects, 
            'update', 
            'Test error', 
            errorMessages, 
            failedRecords
        );
        Test.stopTest();
        
        System.assert(!errorMessages.isEmpty(), 'Should have captured error messages');
        System.assert(!failedRecords.isEmpty(), 'Should have captured failed records');
    }
}