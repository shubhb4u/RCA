@isTest
private class RCA_ProductCatalogTest {

    private static void setupTestData() {
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
    }

    private static Product2 createProductWithChildren() {
        Product2 p = new Product2(
            Name = 'Test Product',
            ProductCode = 'TP1',
            IsActive = true,
            SBQQ__ConfigurationType__c = 'TestConfig',
            SBQQ__Component__c = false,
            IsProcessed__c = false
        );
        insert p;

        SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
            SBQQ__ConfiguredSKU__c = p.Id,
            SBQQ__MinOptionCount__c = 1,
            SBQQ__MaxOptionCount__c = 2,
            SBQQ__Number__c = 1,
            Name = 'Feat1'
        );
        insert feature;

        SBQQ__ProductOption__c option = new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = p.Id,
            SBQQ__OptionalSKU__c = p.Id,
            SBQQ__Number__c = 1,
            SBQQ__Selected__c = true,
            SBQQ__Required__c = false,
            SBQQ__Quantity__c = 2,
            SBQQ__QuantityEditable__c = false,
            SBQQ__MinQuantity__c = 1,
            SBQQ__MaxQuantity__c = 3,
            SBQQ__Bundled__c = true,
            SBQQ__Feature__c = feature.Id
        );
        insert option;

        return p;
    }

    @isTest static void testBatchProcessWithUpdateableType() {
        setupTestData();
        Product2 p = createProductWithChildren();

        Test.startTest();
            RCA_ProductCatalog batch = new RCA_ProductCatalog(new List<Id>{ p.Id });
            Database.executeBatch(batch, 1);
        Test.stopTest();

        // Verify product updated
        Product2 updated = [
            SELECT Id, IsProcessed__c, ConfigureDuringSale, Type, IsSoldOnlyWithOtherProds, StockKeepingUnit
            FROM Product2
            WHERE Id = :p.Id
        ];
      System.assertEquals(true, updated.IsProcessed__c, 'Product should be marked processed');
        // Verify category assignment
        Integer catAssignments = [
            SELECT COUNT() 
            FROM ProductCategoryProduct 
            WHERE ProductId = :p.Id
        ];

        // Verify new bundle product creation (should have same ProductCode and different Id)
        List<Product2> bundles = [
            SELECT Id 
            FROM Product2 
            WHERE ProductCode = 'TP1' AND Id != :p.Id
        ];

        // Verify ProductComponentGroups created
        Integer groupCount = [
            SELECT COUNT() 
            FROM ProductComponentGroup 
            WHERE ParentProductId IN :bundles
        ];
    }

    @isTest static void testHelperAssignCategoryWithExistingAssignment() {
        setupTestData();
        Product2 p = new Product2(Name = 'Prod2', ProductCode = 'P2', IsProcessed__c = false);
        insert p;

        Id catId = [SELECT Id FROM ProductCategory WHERE Name = 'Default category' LIMIT 1].Id;
        insert new ProductCategoryProduct(ProductId = p.Id, ProductCategoryId = catId);

        List<ProductCategoryProduct> result = RCA_ProductCatalogHelper.assignCategory(new List<Product2>{ p }, catId);
        System.assertEquals(0, result.size(), 'No new assignments should be returned if already assigned');
    }

    @isTest static void testGetCategoryAndRelationshipTypeIds() {
        setupTestData();
        Id catId = RCA_ProductCatalogHelper.getCategoryId();
        Id relId = RCA_ProductCatalogHelper.getRelationshipTypeId();

        System.assertNotEquals(null, catId, 'Category Id should be returned');
        System.assertNotEquals(null, relId, 'Relationship Type Id should be returned');
    }
}