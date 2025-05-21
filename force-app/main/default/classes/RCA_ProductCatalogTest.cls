@isTest
private class RCA_ProductCatalogTest {
    
    // Setup default catalog, category, and relationship type for tests
    private static void setupTestData() {
        // Create a test ProductCatalog
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;

        // Create default ProductCategory
        ProductCategory cat = new ProductCategory(
            Name = 'Default category',
            CatalogId = catalog.Id
        );
        insert cat;

        // Create default ProductRelationshipType
        ProductRelationshipType prt = new ProductRelationshipType(
            MainProductRoleCat = 'Bundle',
            AssociatedProductRoleCat = 'BundleComponent',
            Name = 'Bundle to bundle'
        );
        insert prt;
    }

    // Create a test Product2 record with one feature and one option
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

        // Verify Product2 was marked processed and updated correctly
        Product2 updated = [
            SELECT Id, IsProcessed__c, ConfigureDuringSale, Type, IsSoldOnlyWithOtherProds
            FROM Product2
            WHERE Id = :p.Id
        ];
        System.assertEquals(true, updated.IsProcessed__c, 'Product should be marked processed');
        System.assertEquals('TestConfig', updated.ConfigureDuringSale, 'ConfigureDuringSale should match source config');
        System.assertEquals('Bundle', updated.Type, 'Product Type should be updated to Bundle');
        System.assertEquals(false, updated.IsSoldOnlyWithOtherProds, 'IsSoldOnlyWithOtherProds should mirror SBQQ__Component__c');

        // Since Type is updateable, no new bundles, groups, or categories are created
        Integer bundleCount = [SELECT COUNT() FROM Product2 WHERE Id != :p.Id AND ProductCode = 'TP1'];
        System.assertEquals(0, bundleCount, 'No new bundle products should be created');

        Integer catAssignments = [SELECT COUNT() FROM ProductCategoryProduct WHERE ProductId = :p.Id];
        System.assertEquals(0, catAssignments, 'No category assignments for update-only flow');

        Integer groupCount = [SELECT COUNT() FROM ProductComponentGroup WHERE ParentProductId = :p.Id];
        System.assertEquals(0, groupCount, 'No component groups for update-only flow');
    }

    @isTest static void testHelperAssignCategoryWithExistingAssignment() {
        setupTestData();
        Product2 p = new Product2(Name = 'Prod2', ProductCode = 'P2', IsProcessed__c = false);
        insert p;
        Id catId = [SELECT Id FROM ProductCategory WHERE Name = 'Default category' LIMIT 1].Id;
        insert new ProductCategoryProduct(ProductId = p.Id, ProductCategoryId = catId);

        List<ProductCategoryProduct> result = RCA_ProductCatalogHelper.assignCategory(new List<Product2>{ p }, catId);
        System.assertEquals(0, result.size(), 'No new assignments when already present');
    }

    @isTest static void testGetCategoryAndRelationshipTypeIds() {
        setupTestData();
        Id catId = RCA_ProductCatalogHelper.getCategoryId();
        Id relId = RCA_ProductCatalogHelper.getRelationshipTypeId();
        System.assertNotEquals(null, catId, 'getCategoryId should return a valid ID');
        System.assertNotEquals(null, relId, 'getRelationshipTypeId should return a valid ID');
    }
}
