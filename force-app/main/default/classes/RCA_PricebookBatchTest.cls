@isTest
private class RCA_PricebookBatchTest {

    @testSetup
    static void setupData() {
        Id standardPBId = Test.getStandardPricebookId();

        // Insert a valid ProductSellingModel
        ProductSellingModel psm = new ProductSellingModel(
            Name = 'OneTime',
            SellingModelType = 'OneTime',
            Status = 'Active'
        );
        insert psm;

        // Create old (non-bundle) product
        Product2 oldProduct = new Product2(
            Name = 'Old Product',
            StockKeepingUnit = 'SKU123',
            IsActive = true
        );
        insert oldProduct;

        // Create ProductSellingModelOption for old product
        ProductSellingModelOption oldPsmo = new ProductSellingModelOption(
            Product2Id = oldProduct.Id,
            ProductSellingModelId = psm.Id
        );
        insert oldPsmo;

        // Create PricebookEntry for old product
        PricebookEntry oldPBE = new PricebookEntry(
            Product2Id = oldProduct.Id,
            Pricebook2Id = standardPBId,
            ProductSellingModelId = psm.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert oldPBE;

        // Create new bundle product (post-migration)
        Product2 newProduct = new Product2(
            Name = 'Bundle Product',
            StockKeepingUnit = 'SKU123 - Bundle',
            IsActive = true,
            Type = 'Bundle'
        );
        insert newProduct;
    }

    @isTest
    static void testRcaPricebookBatch() {
        // Fetch ProductSellingModelId
        Id psmId = [SELECT Id FROM ProductSellingModel WHERE Name = 'OneTime' LIMIT 1].Id;

        RCA_PricebookBatch batch = new RCA_PricebookBatch();
        batch.pricebookId = Test.getStandardPricebookId();
        batch.productType = 'Bundle';
        batch.psmoId = psmId;

        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();

        // Assert: One ProductSellingModelOption created for new product
        List<ProductSellingModelOption> psmoList = [
            SELECT Id, Product2Id, ProductSellingModelId
            FROM ProductSellingModelOption
            WHERE ProductSellingModelId = :psmId
        ];
        System.assertEquals(2, psmoList.size(), 'Two ProductSellingModelOptions should exist (1 old + 1 new).');

        // Assert: New PricebookEntry created for bundle
        List<PricebookEntry> pbeList = [
            SELECT Id, Product2.StockKeepingUnit, UnitPrice
            FROM PricebookEntry
            WHERE Product2.StockKeepingUnit = 'SKU123 - Bundle'
        ];
        System.assertEquals(1, pbeList.size(), 'One new PricebookEntry should be inserted for the bundle product.');
        System.assertEquals(200, pbeList[0].UnitPrice, 'Unit price should match the old product\'s price.');
    }
}