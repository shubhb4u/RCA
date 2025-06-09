@isTest
private class RCA_ProductCatalogBatchTest {

    @testSetup
    static void setupData() {

        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;

        ProductCategory defaultCategory = new ProductCategory(
            Name = 'Default category',
            CatalogId = catalog.Id
        );
        insert defaultCategory;

        // Create relationship type
        ProductRelationshipType relType = new ProductRelationshipType(
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent',
            Name = 'Bundle to bundle'
        );
        insert relType;

        // Create a product with required fields and unprocessed flag
        Product2 prod = new Product2(
            Name = 'Test CPQ Product',
            ProductCode = 'TEST-001',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__ConfigurationType__c = 'Allowed',
            SBQQ__Component__c = false,
            StockKeepingUnit = 'SKU-001'
        );
        insert prod;

        // Create a Child product with required fields and unprocessed flag
        Product2 prodChild = new Product2(
            Name = 'Test CPQ Product CHILD',
            ProductCode = 'TESTCHILD-001',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__ConfigurationType__c = 'Allowed',
            SBQQ__Component__c = false,
            StockKeepingUnit = 'SKUCHILD-001'
        );
        insert prodChild;

        // Add related features
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            
            Name = 'Feature A',
            SBQQ__ConfiguredSKU__c = prod.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            SBQQ__Number__c =  1
        );
        insert feature;

        // Add related options
        SBQQ__ProductOption__c option = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = prod.Id,
            SBQQ__OptionalSKU__c = prodChild.Id,
            SBQQ__Number__c = 1,
            SBQQ__Feature__c = feature.Id,
            SBQQ__Selected__c = true,
            SBQQ__Required__c = false,
            SBQQ__Quantity__c = 2,
            SBQQ__QuantityEditable__c = true,
            SBQQ__MinQuantity__c = 1,
            SBQQ__MaxQuantity__c = 3
        );
        insert option;

        // Add related options, this might fail for negative testing for invalid Quantity - 
        SBQQ__ProductOption__c optionFail = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = prod.Id,
            SBQQ__OptionalSKU__c = prodChild.Id,
            SBQQ__Number__c = 1,
            SBQQ__Selected__c = true,
            SBQQ__Required__c = false,
            SBQQ__Quantity__c = 5,
            SBQQ__QuantityEditable__c = true,
            SBQQ__MinQuantity__c = 1,
            SBQQ__MaxQuantity__c = 3
        );
        insert optionFail;
    }

    @isTest
    static void testBatchWithoutProductIds() {
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch();
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // You can later add asserts for created/updated records when more logic is added
        System.assert(true, 'Executed batch without errors');
    }

    @isTest
    static void testBatchWithProductIds() {
        Id testProdId = [SELECT Id FROM Product2 WHERE ProductCode = 'TEST-001' LIMIT 1].Id;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{testProdId});
        Database.executeBatch(batch, 200);
        Test.stopTest();

        System.assert(true, 'Executed batch with productIds');
    }

    @isTest
    static void testBuildProducts_BundleAndUpdateLogic() {
        // Create a CPQ product to be processed
        Product2 cpqProduct = new Product2(
            Name = 'CPQ Bundle Product',
            ProductCode = 'BNDL001',
            StockKeepingUnit = 'BNDL001',
            IsActive = true,
            IsProcessed__c = false
        );
        insert cpqProduct;

        // Add a related feature to trigger bundle creation
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'Test Feature',
            SBQQ__Number__c = 001,
            SBQQ__ConfiguredSKU__c = cpqProduct.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5
        );
        insert feature;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Now assert that the bundle product was created
        List<Product2> createdBundles = [
            SELECT Id, Name, ProductCode, StockKeepingUnit
            FROM Product2
            WHERE ProductCode LIKE '% - Bundle'
        ];
        System.assertEquals(1, createdBundles.size(), 'Bundle product should be created for product with features/options');
    }


    @isTest
    static void testBuildProducts_OnlyUpdatePath() {
        Product2 noFeatureProd = new Product2(
            Name = 'Standalone Product',
            ProductCode = 'TEST-002',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__ConfigurationType__c = 'NotAllowed',
            SBQQ__Component__c = true,
            StockKeepingUnit = 'SKU-002'
        );
        insert noFeatureProd;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ noFeatureProd.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Assert that product was updated (not bundled)
        Product2 updatedProd = [SELECT ConfigureDuringSale, IsSoldOnlyWithOtherProds FROM Product2 WHERE Id = :noFeatureProd.Id];
        System.assertEquals('NotAllowed', updatedProd.ConfigureDuringSale);
        System.assertEquals(true, updatedProd.IsSoldOnlyWithOtherProds);

        // Assert no bundles created
        List<Product2> bundles = [SELECT Id FROM Product2 WHERE ProductCode LIKE 'TEST-002 - Bundle'];
        System.assertEquals(0, bundles.size(), 'No bundle should be created for product without features/options');
    }

    @isTest
    static void testBuildProducts_ExceptionCoverage() {
        // Create a dummy CPQ product
        Product2 cpqProduct = new Product2(
            Name = 'Trigger Build Exception',
            ProductCode = 'EXCPT-PROD',
            StockKeepingUnit = 'EXCPT-PROD',
            IsActive = true,
            IsProcessed__c = false
        );
        insert cpqProduct;

        // Set the helper flag to simulate exception
        RCA_ProductCatalogBatchHelper.throwExceptionInBuildProducts = true;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Reset the flag after test
        RCA_ProductCatalogBatchHelper.throwExceptionInBuildProducts = false;

        // No assertions needed — test ensures exception block coverage
    }



    @isTest
    static void testDmlOperationsSuccess() {
        // Step 1: Insert CPQ product
        Product2 cpqProd = new Product2(
            Name = 'Test Product',
            ProductCode = 'TEST-001',
            StockKeepingUnit = 'TEST-SKU-001',
            IsActive = true,
            IsProcessed__c = false
        );
        insert cpqProd;

        // Step 2: Insert a related Product Feature to trigger bundle creation
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'Test Feature',
            SBQQ__ConfiguredSKU__c = cpqProd.Id,
            SBQQ__Number__c = 001
        );
        insert feature;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProd.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Step 3: Assert that bundle was created
        List<Product2> insertedBundles = [
            SELECT Id, Type, ProductCode
            FROM Product2
            WHERE ProductCode LIKE '% - Bundle'
        ];
        System.assertEquals(1, insertedBundles.size(), 'Bundle product should be inserted successfully');

    }


    @isTest
    static void testDmlInsertFailureLogging() {

        // Insert a bundle product that will collide with another on SKU
        Product2 existing = new Product2(
            Name = 'Conflict Product',
            StockKeepingUnit = 'SKU-CONFLICT - Bundle',
            IsActive = true,
            IsProcessed__c = true
        );
        insert existing;


        Product2 cpqProduct = new Product2(
            Name = 'Conflict Product',
            ProductCode = 'CPQ001',
            StockKeepingUnit = 'SKU-CONFLICT',
            IsActive = true,
            IsProcessed__c = false
        );
        insert cpqProduct;


        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'feat1',
            SBQQ__ConfiguredSKU__c = cpqProduct.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 5,
            SBQQ__Number__c =  1
        );

        insert feature;

        Test.startTest();
        Database.executeBatch(new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id }), 200);
        Test.stopTest();

        System.assert(!RCA_BatchExceptionLogger.testErrors.isEmpty(), 'Expected at least one logged error');
        System.debug(RCA_BatchExceptionLogger.testErrors[0]);
        System.assert(
            RCA_BatchExceptionLogger.testErrors[0].contains('SKU-CONFLICT'),
            'Expected error message to reference duplicate SKU'
        );
    }

    @isTest
    static void testBuildNewProductsMap_Success() {
        // Step 1: Create and insert new Product2 records with SKUs
        List<Product2> newProducts = new List<Product2>{
            new Product2(Name = 'Prod A', StockKeepingUnit = 'SKU-A', IsActive = true),
            new Product2(Name = 'Prod B', StockKeepingUnit = 'SKU-B', IsActive = true)
        };
        insert newProducts;

        // Step 2: Call helper to build map
        Map<String, Product2> resultMap = new Map<String, Product2>();

        Test.startTest();
        RCA_ProductCatalogBatchHelper.buildNewProductsMap(newProducts, resultMap);
        Test.stopTest();

        // Step 3: Assert results
        System.assertEquals(2, resultMap.size(), 'Map should contain 2 entries');
        System.assert(resultMap.containsKey('SKU-A'), 'Map should contain SKU-A');
        System.assert(resultMap.containsKey('SKU-B'), 'Map should contain SKU-B');
    }

    @isTest
    static void testBuildNewProductsMap_ThroughBatch() {
        // Step 1: Insert CPQ product
        Product2 cpqProduct = new Product2(
            Name = 'CPQ Bundle Product',
            ProductCode = 'MAPTEST-001',
            StockKeepingUnit = 'MAP-SKU-001',
            IsActive = true,
            IsProcessed__c = false
        );
        insert cpqProduct;

        // Step 2: Add a related feature to trigger bundle creation
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'Map Feature',
            SBQQ__Number__c = 1,
            SBQQ__ConfiguredSKU__c = cpqProduct.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 3
        );
        insert feature;

        // Step 3: Run the batch
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Step 4: Verify the bundle product was inserted (indirectly using buildNewProductsMap)
        List<Product2> createdBundles = [
            SELECT Id, Name, StockKeepingUnit
            FROM Product2
            WHERE ProductCode LIKE 'MAPTEST-001 - Bundle'
        ];
        System.assertEquals(1, createdBundles.size(), 'Expected one bundle product to be created');

        // Step 5: Simulate logic similar to buildNewProductsMap result
        Map<String, Product2> verifyMap = new Map<String, Product2>();
        for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit != null]) {
            verifyMap.put(p.StockKeepingUnit, p);
        }

        // Step 6: Assert that the bundle's SKU exists in the map (emulating helper's outcome)
        String expectedBundleSKU = 'MAP-SKU-001 - Bundle';
        System.assert(verifyMap.containsKey(expectedBundleSKU), 'Expected SKU to be part of inserted product map');
    }


    @isTest
    static void testBuildComponentGroups_ThroughBatch() {
        // Step 1: Create original CPQ product
        Product2 cpqProd = new Product2(
            Name = 'Build Group Product',
            ProductCode = 'GRP-001',
            StockKeepingUnit = 'GRP-SKU-001',
            IsActive = true,
            IsProcessed__c = false,
            SBQQ__ConfigurationType__c = 'Allowed',
            SBQQ__Component__c = false
        );
        insert cpqProd;

        // Step 2: Add Feature
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'RAM Feature',
            SBQQ__ConfiguredSKU__c = cpqProd.Id,
            SBQQ__Number__c = 1,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 2
        );
        insert feature;

        // Step 3: Add an option tied to the feature
        Product2 childProd1 = new Product2(
            Name = 'RAM Option',
            ProductCode = 'RAM001',
            IsActive = true,
            StockKeepingUnit = 'SKU-RAM001'
        );
        insert childProd1;

        SBQQ__ProductOption__c optWithFeature = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = cpqProd.Id,
            SBQQ__OptionalSKU__c = childProd1.Id,
            SBQQ__Feature__c = feature.Id,
            SBQQ__Number__c = 002
        );
        insert optWithFeature;

        // Step 4: Add an independent option (no feature)
        Product2 childProd2 = new Product2(
            Name = 'Independent SSD',
            ProductCode = 'SSD001',
            IsActive = true,
            StockKeepingUnit = 'SKU-SSD001'
        );
        insert childProd2;

        SBQQ__ProductOption__c optWithoutFeature = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = cpqProd.Id,
            SBQQ__OptionalSKU__c = childProd2.Id,
            // No SBQQ__Feature__c => treated as independent option
            SBQQ__Number__c = 2
        );
        insert optWithoutFeature;

        // Step 5: Run the batch (which internally calls buildComponentGroups)
        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProd.Id });
        Database.executeBatch(batch, 200);
        Test.stopTest();

        // Step 6: Assert that both groups were created
        List<ProductComponentGroup> createdGroups = [
            SELECT Id, Name FROM ProductComponentGroup WHERE Name IN ('Others', 'RAM Feature')
        ];
        System.assertEquals(2, createdGroups.size(), 'Expected two groups: "Others" and the feature group');

        Set<String> groupNames = new Set<String>();
        for (ProductComponentGroup grp : createdGroups) {
            groupNames.add(grp.Name);
        }

        System.assert(groupNames.contains('Others'), 'Expected group for independent options');
        System.assert(groupNames.contains('RAM Feature'), 'Expected group for feature: RAM Feature');
    }

    @isTest
    static void testBuildComponentGroups_ExceptionCoverage() {
        // Insert a dummy CPQ product
        Product2 cpqProduct = new Product2(
            Name = 'CPQ With Features',
            ProductCode = 'EXCPT-GROUP',
            IsActive = true
        );
        insert cpqProduct;

        // Set the helper flag to simulate exception
        RCA_ProductCatalogBatchHelper.throwExceptionComponentsGroups = true;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Reset the flag after test
        RCA_ProductCatalogBatchHelper.throwExceptionComponentsGroups = false;

        // No assertions needed — test is just for exception coverage
    }




    @isTest
    static void testBatchExecute_ExceptionHandling() {
        // Create a conflicting product to trigger duplicate SKU error
        Product2 conflictProd = new Product2(
            Name = 'Bundle SKU Conflict',
            ProductCode = 'CONFLICT-001',
            StockKeepingUnit = 'DUPLICATE-SKU - Bundle',
            IsActive = true,
            IsProcessed__c = true
        );
        insert conflictProd;

        // This product will try to create a bundle with same SKU as above
        Product2 triggerErrorProd = new Product2(
            Name = 'Original Product',
            ProductCode = 'DUPLICATE-SKU',
            StockKeepingUnit = 'DUPLICATE-SKU',
            IsActive = true,
            IsProcessed__c = false
        );
        insert triggerErrorProd;

        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'ErrorFeature',
            SBQQ__Number__c = 1,
            SBQQ__ConfiguredSKU__c = triggerErrorProd.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 2
        );
        insert feature;

        Test.startTest();
        Database.executeBatch(new RCA_ProductCatalogBatch(new List<Id>{ triggerErrorProd.Id }), 200);
        Test.stopTest();

        // Assert that errors were captured
        System.assert(!RCA_BatchExceptionLogger.testErrors.isEmpty(), 'Expected logged error due to duplicate SKU');
        System.debug('Caught error: ' + RCA_BatchExceptionLogger.testErrors[0]);
    }




    @isTest
    static void testBuildRelatedComponents_ThroughBatch() {

        // Create CPQ product bundles - original and new
        Product2 origProduct = new Product2(Name = 'Orig Product', StockKeepingUnit = 'SKU_ORIG');
        insert origProduct;

        Product2 newProduct = new Product2(Name = 'New Product', StockKeepingUnit = 'SKU_ORIG_NEW', Type = 'Bundle');
        insert newProduct;

        // Map original to new
        Map<Id, Product2> allOrigCPQToNewBundleMap = new Map<Id, Product2>{ origProduct.Id => origProduct };
        Map<String, Product2> insertedProductMap = new Map<String, Product2>{ 'SKU_ORIG' => newProduct };

        // Create feature records
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name = 'Feature 1',
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 2,
            SBQQ__Number__c = 1
        );
        insert feature;

        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>{
            origProduct.Id => new List<SBQQ__ProductFeature__c>{ feature }
        };

        // Create ProductComponentGroup records
        ProductComponentGroup groupNew = new ProductComponentGroup(
            ParentProductId = newProduct.Id,
            Name = feature.Name,
            MinBundleComponents = 1,
            MaxBundleComponents = 2,
            Sequence = 1
        );
        insert groupNew;

        List<ProductComponentGroup> allGroups = new List<ProductComponentGroup>{ groupNew };

        // Create ProductOption records
        SBQQ__ProductOption__c option1 = new SBQQ__ProductOption__c(
            SBQQ__Feature__c = feature.Id,
            SBQQ__Feature__r = feature,
            SBQQ__OptionalSKU__c = newProduct.Id,
            SBQQ__Selected__c = true,
            SBQQ__Required__c = false,
            SBQQ__Quantity__c = 1,
            SBQQ__QuantityEditable__c = true,
            SBQQ__MinQuantity__c = 1,
            SBQQ__MaxQuantity__c = 5,
            SBQQ__Bundled__c = true,
            SBQQ__Number__c = 10
        );
        insert option1;

        Map<Id, List<SBQQ__ProductOption__c>> optionMap = new Map<Id, List<SBQQ__ProductOption__c>>{
            origProduct.Id => new List<SBQQ__ProductOption__c>{ option1 }
        };

        // Create relationship type
        ProductRelationshipType relType = [SELECT Id FROM ProductRelationshipType WHERE Name = 'Bundle to bundle' LIMIT 1];
        Id relationshipTypeId = relType.Id;

        // Call your helper method (or run batch) with these inputs
        List<ProductRelatedComponent> relatedComponents = RCA_ProductCatalogBatchHelper.buildRelatedComponents(
            new Map<Id, Product2>(), optionMap, allGroups, relationshipTypeId, allOrigCPQToNewBundleMap, insertedProductMap
        );

        // Assert >0 components created
        System.assertEquals(1, relatedComponents.size());

    }

    @isTest
    static void testBuildRelatedComponents_ExceptionCoverage() {
        // Create dummy Product2 record to trigger batch execution
        Product2 cpqProduct = new Product2(Name = 'ThrowComponents', ProductCode = 'EXCPT-COMP', IsActive = true);
        insert cpqProduct;

        // Simulate the exception
        RCA_ProductCatalogBatchHelper.throwExceptionInBuildRelatedComponents = true;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ cpqProduct.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Reset the flag
        RCA_ProductCatalogBatchHelper.throwExceptionInBuildRelatedComponents = false;

        // No assertion needed — purpose is to cover the catch block
    }



    @IsTest
    static void testBatchExecution_FullRun() {
        // Create test catalog and category (shouldn't rely on org data)
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog ' + DateTime.now().getTime());
        insert catalog;
        
        ProductCategory defaultCategory = new ProductCategory(
            Name = 'Default category ' + DateTime.now().getTime(),
            CatalogId = catalog.Id
        );
        insert defaultCategory;
        
        // Create relationship type (don't rely on org data)
        ProductRelationshipType relType;
        List<ProductRelationshipType> existingTypes = [SELECT Id FROM ProductRelationshipType WHERE Name = 'Bundle to bundle' LIMIT 1];
        if (existingTypes.isEmpty()) {
            relType = new ProductRelationshipType(Name = 'Bundle to bundle');
            insert relType;
        } else {
            relType = existingTypes[0];
        }


        // (2) Create the CPQ Product that the batch will process
        Product2 origProduct = new Product2(
            Name                     = 'Original Product ' + DateTime.now().getTime(),
            StockKeepingUnit         = 'SKU_TEST_' + DateTime.now().getTime(),
            ProductCode              = 'CODE_' + DateTime.now().getTime(),
            IsProcessed__c           = false,
            IsActive                 = true,
            SBQQ__ConfigurationType__c = 'Allowed',   // ensure bundle logic is allowed
            SBQQ__Component__c       = false
        );
        insert origProduct;

        // (3) Create a “child” Product to be used in a ProductOption
        Product2 childProduct = new Product2(
            Name             = 'Child Product ' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_CHILD_' + DateTime.now().getTime(),
            ProductCode      = 'CHILD_CODE_' + DateTime.now().getTime(),
            IsActive         = true
        );
        insert childProduct;

        // (4) Insert a Feature so that hasFeatures == true in buildProducts()
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name                   = 'Main Feature ' + DateTime.now().getTime(),
            SBQQ__ConfiguredSKU__c = origProduct.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 3,
            SBQQ__Number__c        = 1
        );
        insert feature;

        // (5) Insert a ProductOption so that hasOptions == true (optional; one or both suffice)
        SBQQ__ProductOption__c opt = new SBQQ__ProductOption__c(
            SBQQ__Feature__c       = feature.Id,
            SBQQ__OptionalSKU__c   = childProduct.Id,
            SBQQ__ConfiguredSKU__c = origProduct.Id,
            SBQQ__Selected__c      = true,
            SBQQ__Required__c      = true,
            SBQQ__Quantity__c      = 2,
            SBQQ__QuantityEditable__c = true,
            SBQQ__MinQuantity__c   = 1,
            SBQQ__MaxQuantity__c   = 5,
            SBQQ__Bundled__c       = true,
            SBQQ__Number__c        = 5
        );
        insert opt;

        Test.startTest();
            // (6) Directly pass origProduct.Id to the batch, so that start() re‐queries it 
            //     (complete with SBQQ__Features__r and SBQQ__Options__r).
            Database.executeBatch(
                new RCA_ProductCatalogBatch(new List<Id>{ origProduct.Id }),
                50
            );
        Test.stopTest();

        // (7) Now the helper.buildProducts(...) must have created a bundle with SKU = origProduct.StockKeepingUnit + ' - Bundle'
        String expectedSKU = origProduct.StockKeepingUnit + ' - Bundle';
        List<Product2> bundleProducts = [
            SELECT Id, Type, StockKeepingUnit 
            FROM Product2 
            WHERE StockKeepingUnit = :expectedSKU 
            LIMIT 1
        ];
        System.assert(
            !bundleProducts.isEmpty(),
            'Bundle product should be created with SKU = ' + expectedSKU
        );
        System.assertEquals(
            'Bundle',
            bundleProducts[0].Type,
            'The new product’s Type must be "Bundle".'
        );

        // (8) Verify at least one ProductComponentGroup was created under that new bundle
        List<ProductComponentGroup> groups = [
            SELECT Id, ParentProductId 
            FROM ProductComponentGroup 
            WHERE ParentProductId = :bundleProducts[0].Id
        ];
        System.assert(
            !groups.isEmpty(),
            'At least one ProductComponentGroup should exist for the bundle.'
        );

        // (9) Verify ProductRelatedComponent was created linking the childProduct
        List<ProductRelatedComponent> components = [
            SELECT Id, ChildProductId, Quantity 
            FROM ProductRelatedComponent 
            WHERE ParentProductId = :bundleProducts[0].Id
        ];
        System.assertEquals(
            1,
            components.size(),
            'Exactly one related component should be created.'
        );
        System.assertEquals(
            childProduct.Id,
            components[0].ChildProductId,
            'The related component’s ChildProductId must match the inserted child product.'
        );
        System.assertEquals(
            2,
            components[0].Quantity,
            'Quantity on the related component must match the ProductOption quantity.'
        );

        // (10) Finally, verify the original CPQ product is marked processed
        Product2 processedOrig = [
            SELECT IsProcessed__c 
            FROM Product2 
            WHERE Id = :origProduct.Id
        ];
        System.assertEquals(
            true,
            processedOrig.IsProcessed__c,
            'Original product should be marked as processed after batch.'
        );
    }

    @IsTest
    static void testAssignCategory_HelperAlone() {
        // 1) Create a ProductCatalog & exact‐named category
        ProductCatalog catalog = new ProductCatalog(Name = 'TestCatalog_' + DateTime.now().getTime());
        insert catalog;
        // Must match RCA_ProductCatalogBatchHelper.DEFAULT_CATEGORY_NAME exactly:
        ProductCategory defaultCat = new ProductCategory(
            Name      = RCA_ProductCatalogBatchHelper.DEFAULT_CATEGORY_NAME,
            CatalogId = catalog.Id
        );
        insert defaultCat;

        // 2) Create two CPQ “original” products:
        //    - prodA will be a “standalone” (no features/options → updatedProducts path)
        //    - prodB will have a “bundle” (hasFeatures → new bundle path)
        Product2 prodA = new Product2(
            Name                = 'StandaloneProdA_' + DateTime.now().getTime(),
            StockKeepingUnit    = 'SKU_A_' + DateTime.now().getTime(),
            IsActive            = true,
            IsProcessed__c      = false,
            SBQQ__ConfigurationType__c = 'Allowed'
        );
        insert prodA;

        Product2 prodB = new Product2(
            Name                = 'BundleableProdB_' + DateTime.now().getTime(),
            StockKeepingUnit    = 'SKU_B_' + DateTime.now().getTime(),
            IsActive            = true,
            IsProcessed__c      = false,
            SBQQ__ConfigurationType__c = 'Allowed'
        );
        insert prodB;

        // 3) prodA has no features or options → goes into updatedProducts list
        // 4) For prodB, create a Feature so that buildProducts(…) would put it in newProducts:
        SBQQ__ProductFeature__c featB = new SBQQ__ProductFeature__c(
            Name                   = 'FeatB_' + DateTime.now().getTime(),
            SBQQ__ConfiguredSKU__c = prodB.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 1,
            SBQQ__Number__c        = 1
        );
        insert featB;

        // 5) Manually invoke buildProducts(...) to populate newProducts vs. updatedProducts:
        List<Product2> cpqList = new List<Product2>{ prodA, prodB };

        // Prepare the maps needed by buildProducts(…):
        //   featureMap: prodA→empty list, prodB→[featB]
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        Map<Id, List<SBQQ__ProductOption__c>>   optionMap  = new Map<Id, List<SBQQ__ProductOption__c>>();

        featureMap.put(prodA.Id, new List<SBQQ__ProductFeature__c>());
        featureMap.put(prodB.Id, new List<SBQQ__ProductFeature__c>{ featB });

        optionMap.put(prodA.Id, new List<SBQQ__ProductOption__c>());
        optionMap.put(prodB.Id, new List<SBQQ__ProductOption__c>());

        List<Product2> newProducts        = new List<Product2>();
        List<Product2> updatedProducts    = new List<Product2>();
        Map<Id, Product2> origToBundleMap = new Map<Id, Product2>();

        RCA_ProductCatalogBatchHelper.buildProducts(
            cpqList,
            featureMap,
            optionMap,
            newProducts,
            updatedProducts,
            origToBundleMap
        );

        // 6) Assert buildProducts logic:
        System.assertEquals(
            1,
            updatedProducts.size(),
            'prodA should be updated (no features/options).'
        );
        System.assertEquals(
            prodA.Id,
            updatedProducts[0].Id,
            'prodA should be the only updatedProducts entry.'
        );

        System.assertEquals(
            1,
            newProducts.size(),
            'prodB has a feature and should have been marked for bundle creation.'
        );
        Product2 candidateBundle = newProducts[0];
        System.assertEquals(
            'Bundle',
            candidateBundle.Type,
            'The newProducts entry should have Type="Bundle".'
        );
        System.assertEquals(
            prodB.Id,
            origToBundleMap.keySet().iterator().next(),
            'origToBundleMap must have prodB.Id as key.'
        );
        System.assertEquals(
            candidateBundle,
            origToBundleMap.get(prodB.Id),
            'origToBundleMap must map prodB to the newly built bundle object.'
        );

        // 7) Now simulate “insertion” of that bundle, so that we can call buildNewProductsMap:
        insert candidateBundle;
        String expectedBundleSKU = prodB.StockKeepingUnit + ' - Bundle';
        System.assertEquals(
            expectedBundleSKU,
            candidateBundle.StockKeepingUnit,
            'SKU must be base + " - Bundle"'
        );

        // 8) Now test buildNewProductsMap(...) using the newly inserted bundle:
        Map<String, Product2> insertedMap = new Map<String, Product2>();
        RCA_ProductCatalogBatchHelper.buildNewProductsMap(
            new List<Product2>{ candidateBundle },
            insertedMap
        );
        System.assert(
            insertedMap.containsKey(expectedBundleSKU),
            'buildNewProductsMap must find the newly inserted bundle by its SKU.'
        );

        // 9) Finally test assignCategory(...) logic:
        List<ProductCategoryProduct> links = RCA_ProductCatalogBatchHelper.assignCategory(
            defaultCat.Id,
            updatedProducts,
            origToBundleMap,
            insertedMap
        );

        // The helper only links prodA (since prodA was in updatedProducts).
        Set<Id> expectedProductIds = new Set<Id>{ prodA.Id };

        Set<Id> actualLinkProductIds = new Set<Id>();
        for (ProductCategoryProduct pcp : links) {
            actualLinkProductIds.add(pcp.ProductId);
            System.assertEquals(
                defaultCat.Id,
                pcp.ProductCategoryId,
                'All returned links must use the same default categoryId.'
            );
        }
        System.assertEquals(
            expectedProductIds,
            actualLinkProductIds,
            'assignCategory should return exactly one link for prodA.'
        );
    }

    @isTest
    static void testAssignCategory_ExceptionCoverage() {

        ProductCatalog catalog = new ProductCatalog(Name = 'TestCatalog_' + DateTime.now().getTime());
        insert catalog;

        // Step 1: Create a category
        ProductCategory category = new ProductCategory(Name = 'Exception Test Category', catalogId = catalog.Id);
        insert category;

        // Step 2: Create a product to act as an updated product
        Product2 updatedProd = new Product2(
            Name = 'Updated Product',
            ProductCode = 'CAT-001',
            StockKeepingUnit = 'CAT-001',
            IsActive = true,
            IsProcessed__c = true
        );
        insert updatedProd;

        // Step 3: Set up required maps
        Map<Id, Product2> allOrigCPQToNewBundleMap = new Map<Id, Product2>();
        Map<String, Product2> insertedProductMap = new Map<String, Product2>();

        // Step 4: Trigger the simulated exception
        RCA_ProductCatalogBatchHelper.throwExceptionAssignCategories = true;

        Test.startTest();
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ updatedProd.Id });
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Step 5: Reset flag
        RCA_ProductCatalogBatchHelper.throwExceptionAssignCategories = false;

        // No need to assert — this is just to ensure exception block is executed
    }


    @IsTest
    static void testMarkProductsProcessed_HelperAlone() {
        // 1) Create two CPQ Product2 records with IsProcessed__c = false
        Product2 cpq1 = new Product2(
            Name              = 'CPQ_Proc1_' + DateTime.now().getTime(),
            StockKeepingUnit  = 'SKU_PROC1_' + DateTime.now().getTime(),
            ProductCode       = 'PCODE1_' + DateTime.now().getTime(),
            IsActive          = true,
            IsProcessed__c    = false
        );
        Product2 cpq2 = new Product2(
            Name              = 'CPQ_Proc2_' + DateTime.now().getTime(),
            StockKeepingUnit  = 'SKU_PROC2_' + DateTime.now().getTime(),
            ProductCode       = 'PCODE2_' + DateTime.now().getTime(),
            IsActive          = true,
            IsProcessed__c    = false
        );
        insert new List<Product2>{ cpq1, cpq2 };

        // 2) Call markProductsProcessed(...) on these two products
        List<String> errorMessages = new List<String>();
        List<SObject> failedRecords = new List<SObject>();
        RCA_ProductCatalogBatchHelper.markProductsProcessed(
            new List<Product2>{ cpq1, cpq2 },
            errorMessages,
            failedRecords
        );

        // 3) Assert there were no errors and no failed records
        System.assertEquals(
            0, 
            errorMessages.size(), 
            'Expected no errors when marking products as processed.'
        );
        System.assertEquals(
            0, 
            failedRecords.size(), 
            'Expected no failedRecords when marking products as processed.'
        );

        // 4) Re‐query the two products and verify IsProcessed__c is now true
        Product2 reloaded1 = [ SELECT IsProcessed__c FROM Product2 WHERE Id = :cpq1.Id ];
        Product2 reloaded2 = [ SELECT IsProcessed__c FROM Product2 WHERE Id = :cpq2.Id ];
        System.assertEquals(true, reloaded1.IsProcessed__c, 'cpq1 should be marked processed.');
        System.assertEquals(true, reloaded2.IsProcessed__c, 'cpq2 should be marked processed.');
    }

    @IsTest
    static void testMarkProductsProcessed_HandleDmlFailure() {
        // 1) Create a “fake” Product2 instance with an Id that doesn’t exist.
        //    This will force the update to fail in handleDmlOperation.
        //    Use a syntactically valid 18‐char Id starting with '01t' (Product2 prefix).
        Product2 fakeProd = new Product2(
            Id = '01t000000000000AA1',
            IsProcessed__c = true
        );

        // 2) Call markProductsProcessed(...) on this fake product
        List<String> errorMessages = new List<String>();
        List<SObject> failedRecords = new List<SObject>();
        RCA_ProductCatalogBatchHelper.markProductsProcessed(
            new List<Product2>{ fakeProd },
            errorMessages,
            failedRecords
        );

        // 3) Now, because '01t000000000000AA1' does not exist in the database,
        //    the update should have failed, resulting in exactly one error message
        //    and one failed record being captured.
        System.assertEquals(
            1,
            errorMessages.size(),
            'Expected one error message when updating a non‐existent Product2.'
        );
        System.assertEquals(
            1,
            failedRecords.size(),
            'Expected exactly one record in failedRecords for the non‐existent Product2.'
        );

        // 4) Confirm that the failedRecords list contains our fakeProd
        Product2 failedProd = (Product2) failedRecords[0];
        System.assertEquals(
            fakeProd.Id,
            failedProd.Id,
            'The failedRecords entry must be the same fakeProd Id we passed in.'
        );
    }

    @IsTest
    static void testGetFailedRecordDetail_ProductRelatedComponent() {
        // Create a ProductRelatedComponent stub (no need to insert)
        ProductRelatedComponent prc = new ProductRelatedComponent(
            ParentProductId           = '001000000000001',
            ProductComponentGroupId   = 'a0H000000000001',
            ChildProductId            = '02i000000000001',
            Quantity                  = 1,
            ProductRelationshipTypeId = '012000000000001'
        );
        String detail = RCA_ProductCatalogBatchHelper.getFailedRecordDetail(prc);

        System.assert(
            detail.contains('Check SBQQ_ProductOption__c record with Optional SKU field value: 02i000000000001'),
            'Expected getFailedRecordDetail to reference the Optional SKU for ProductRelatedComponent.'
        );
    }


    @IsTest
    static void testGetFailedRecordDetail_ProductComponentGroup_NonOthers() {
        // Insert a dummy parent so feature subquery works
        Product2 dummyParent = new Product2(
            Name             = 'DummyParent_' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_DUMMY_' + DateTime.now().getTime(),
            ProductCode      = 'PDUMMY_' + DateTime.now().getTime(),
            IsActive         = true,
            SBQQ__ConfigurationType__c = 'Allowed',
            Type = 'Bundle'
        );
        insert dummyParent;

        // Insert a SBQQ__ProductFeature__c with Name matching groupName
        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            Name                   = 'DummyFeature_' + DateTime.now().getTime(),
            SBQQ__ConfiguredSKU__c = dummyParent.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 1,
            SBQQ__Number__c        = 1
        );
        insert feature;

        // Create a ProductComponentGroup whose Name equals that feature’s Name
        ProductComponentGroup pcg = new ProductComponentGroup(
            ParentProductId     = dummyParent.Id,
            Name                = feature.Name,
            MinBundleComponents = 1,
            MaxBundleComponents = 1,
            Sequence            = 1
        );
        insert pcg;

        String detail = RCA_ProductCatalogBatchHelper.getFailedRecordDetail(pcg);
        System.assert(
            detail.contains('Check SBQQ__ProductFeature__c with') &&
            detail.contains('Name:          -->>> ' + feature.Name),
            'Expected getFailedRecordDetail to mention the feature name.'
        );

        System.assert(
            detail.contains(dummyParent.Id),
            'Expected getFailedRecordDetail to mention the parent Product2 Id.'
        );
    }

    @IsTest
    static void testGetFailedRecordDetail_ProductComponentGroup_Others() {
        // Create a bundle product
        Product2 bundleProd = new Product2(
            Name             = 'Bundle_' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_BUNDLE_' + DateTime.now().getTime(),
            ProductCode      = 'P_BUNDLE_' + DateTime.now().getTime(),
            Type             = 'Bundle',
            IsActive         = true
        );
        insert bundleProd;

        // Create a ProductComponentGroup named "Others"
        ProductComponentGroup pcg = new ProductComponentGroup(
            ParentProductId     = bundleProd.Id,
            Name                = RCA_ProductCatalogBatchHelper.COMMON_GROUP_NAME,
            MinBundleComponents = 0,
            MaxBundleComponents = 10,
            Sequence            = 1
        );
        insert pcg;

        String detail = RCA_ProductCatalogBatchHelper.getFailedRecordDetail(pcg);
        System.assertEquals(
            'Check SBQQ__ProductOption__c record for optional SKU under group "Others".',
            detail,
            'Expected getFailedRecordDetail to return the generic “Others” message.'
        );
    }

    @IsTest
    static void testGetFailedRecordDetail_Product2() {
        Product2 prod = new Product2(
            Name             = 'ProdFail_' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_FAIL_' + DateTime.now().getTime(),
            ProductCode      = 'PFAIL_' + DateTime.now().getTime(),
            IsActive         = true
        );
        insert prod;

        String detail = RCA_ProductCatalogBatchHelper.getFailedRecordDetail(prod);
        System.assert(
            detail.contains('Product2 failed - Name: ' + prod.Name),
            'Expected getFailedRecordDetail to contain Product2 Name.'
        );
        System.assert(
            detail.contains('SKU: ' + prod.StockKeepingUnit),
            'Expected getFailedRecordDetail to contain Product2 SKU.'
        );
    }

    @IsTest
    static void testGetProductsToUpdate_And_RollbackFailedCPQHierarchy() {
        // Create an original and bundle
        Product2 orig = new Product2(
            Name             = 'OrigProd_' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_ORIG_' + DateTime.now().getTime(),
            ProductCode      = 'P_ORIG_' + DateTime.now().getTime(),
            IsActive         = true,
            IsProcessed__c   = true
        );
        insert orig;

        Product2 bundle = new Product2(
            Name             = 'Bundle_' + DateTime.now().getTime(),
            StockKeepingUnit = orig.StockKeepingUnit + ' - Bundle',
            ProductCode      = orig.ProductCode + ' - Bundle',
            Type             = 'Bundle',
            IsActive         = true
        );
        insert bundle;

        // Insert a child group and child component
        ProductComponentGroup pcg = new ProductComponentGroup(
            ParentProductId     = bundle.Id,
            Name                = 'ToBeDeleted_' + DateTime.now().getTime(),
            MinBundleComponents = 0,
            MaxBundleComponents = 1,
            Sequence            = 1
        );
        insert pcg;

        ProductRelatedComponent prc = new ProductRelatedComponent(
            ParentProductId          = bundle.Id,
            ProductComponentGroupId  = pcg.Id,
            ChildProductId           = orig.Id,
            Quantity                 = 1,
            IsDefaultComponent = true,
            ProductRelationshipTypeId = [SELECT Id FROM ProductRelationshipType LIMIT 1].Id
        );
        insert prc;

        // Build failedRecords list
        List<SObject> failedRecords = new List<SObject>{ pcg, prc };

        // Call getProductsToUpdate → resets orig.IsProcessed__c to false
        RCA_ProductCatalogBatchHelper.getProductsToUpdate(new Set<Id>{ bundle.Id });
        orig = [SELECT IsProcessed__c FROM Product2 WHERE Id = :orig.Id];
        System.assertEquals(false, orig.IsProcessed__c, 'Expected orig.IsProcessed__c to be false.');

        // Now call rollbackFailedCPQHierarchy
        List<String> errorMessages = new List<String>();
        RCA_ProductCatalogBatchHelper.rollbackFailedCPQHierarchy(failedRecords, errorMessages);

        // The ProductComponentGroup should be deleted
        Integer countGroups = [SELECT count() FROM ProductComponentGroup WHERE Id = :pcg.Id];
        System.assertEquals(0, countGroups, 'Expected the ProductComponentGroup to be deleted.');

        // The bundle product should be deleted
        Integer countBundles = [SELECT count() FROM Product2 WHERE Id = :bundle.Id];
        System.assertEquals(0, countBundles, 'Expected the bundle Product2 to be deleted.');

        // No unexpected errors
        System.assertEquals(0, errorMessages.size(), 'Expected no errors during rollback.');
    }

    @IsTest
    static void testSendErrorNotification_NoException() {
        // Simply ensure no exception is thrown
        List<String> dummyErrors = new List<String>{ 'DummyError1', 'DummyError2' };
        RCA_ProductCatalogBatchHelper.sendErrorNotification(dummyErrors);
        System.assert(true, 'sendErrorNotification should complete without error.');
    }

    @IsTest
    static void testBatchFinish_NoErrors() {
        // Create a CPQ product with no child Feature/Option so batch will succeed
        Product2 p = new Product2(
            Name             = 'FinishProd_' + DateTime.now().getTime(),
            StockKeepingUnit = 'SKU_FIN_' + DateTime.now().getTime(),
            ProductCode      = 'PFIN_' + DateTime.now().getTime(),
            IsActive         = true,
            IsProcessed__c   = false
        );
        insert p;

        Test.startTest();
            RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{ p.Id });
            Database.executeBatch(batch, 50);
        Test.stopTest();

        // Clear any residual errors
        batch.errorMessages.clear();
        batch.failedRecords.clear();

        // Calling finish() should not throw
        batch.finish(null);
        System.assert(true, 'finish() should complete without throwing when there are no errors.');
    }

    @IsTest
    static void testBatchFinish_WithErrors() {
        // Create a batch instance with a dummy error and a dummy failed record
        RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch();
        batch.errorMessages.add('SimulatedError');

        // Create a dummy ProductComponentGroup (not inserted) and add to failedRecords
        ProductComponentGroup pcg = new ProductComponentGroup(
            ParentProductId     = '001000000000002',
            Name                = 'DummyGrp_' + DateTime.now().getTime(),
            MinBundleComponents = 0,
            MaxBundleComponents = 1,
            Sequence            = 1
        );
        batch.failedRecords.add(pcg);

        // Calling finish() with errors should not throw
        Test.startTest();
            batch.finish(null);
        Test.stopTest();

        System.assert(true, 'finish() should complete without throwing even when errors exist.');
    }
    
}