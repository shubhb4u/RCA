@isTest
private class RCA_PricebookBatchVersion2Test {

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

        // Insert Custom Metadata record: Pricing_Method_Config__mdt
        // Since we cannot insert custom metadata in tests directly via Apex, use Test.loadData
        // So, this part must be assumed to exist in the org beforehand for full end-to-end test
        // But for simulation in test class, we manually mock the values used in helper class

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

        // Create new bundle product
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
        Id psmId = [SELECT Id FROM ProductSellingModel WHERE Name = 'OneTime' LIMIT 1].Id;
        Id pbId = Test.getStandardPricebookId();

        // Simulate batch execution (we assume the custom metadata has 'Bundle' as ProductType__c)
        Test.startTest();
        Database.executeBatch(new RCA_PricebookBatchVersion2(), 1);
        Test.stopTest();

        // Assert PSMO creation (1 for old + 1 for bundle)
        List<ProductSellingModelOption> psmoList = [
            SELECT Id, Product2Id, ProductSellingModelId
            FROM ProductSellingModelOption
            WHERE ProductSellingModelId = :psmId
        ];
        System.assertEquals(2, psmoList.size(), 'Two ProductSellingModelOptions should exist (1 old + 1 new).');

        // Assert PricebookEntry creation for bundle product
        List<PricebookEntry> pbeList = [
            SELECT Id, Product2.StockKeepingUnit, UnitPrice
            FROM PricebookEntry
            WHERE Product2.StockKeepingUnit = 'SKU123 - Bundle'
        ];
        System.assertEquals(1, pbeList.size(), 'One new PricebookEntry should be inserted for the bundle product.');
        System.assertEquals(200, pbeList[0].UnitPrice, 'Unit price should match the old product\'s price.');
    }
}