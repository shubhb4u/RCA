@isTest
private class RCA_PricebookBatchTest {
	@testSetup
    static void testDataSetup(){
        Id standardPBId = Test.getStandardPricebookId();
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.StockKeepingUnit = 'TP-01';
        product.ProductCode = 'TP-01';
        product.IsActive=True;
        insert product;
        
        
        ProductSellingModel psm = new ProductSellingModel(
            Name = 'OneTime',
            SellingModelType = 'OneTime',
            Status = 'Active'
        );
        insert psm;
        
        
        ProductSellingModelOption productPsmo = new ProductSellingModelOption(
            Product2Id = product.Id,
            ProductSellingModelId = psm.Id
        );
        insert productPsmo;
        
        PricebookEntry productPBE = new PricebookEntry(
            Product2Id = product.Id,
            Pricebook2Id = standardPBId,
            ProductSellingModelId = psm.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert productPBE;

        
        Product2 newBundleProduct = new Product2();
        newBundleProduct.Name = 'Bundle Test Product';
        newBundleProduct.StockKeepingUnit = product.StockKeepingUnit+'Bundle';
        newBundleProduct.ProductCode= product.StockKeepingUnit+'Bundle';
        newBundleProduct.Type='Bundle';
        newBundleProduct.IsActive=True;
        insert newBundleProduct;
        
        
        
        Product2 santdaloneProduct = new Product2();
        santdaloneProduct.Name = 'Standalone Test Product';
        santdaloneProduct.StockKeepingUnit = 'STP-001';
        santdaloneProduct.ProductCode='STP-001';
        santdaloneProduct.IsActive=True;
        insert santdaloneProduct;
        
        ProductSellingModelOption santdaloneProductPsmo = new ProductSellingModelOption(
            Product2Id = santdaloneProduct.Id,
            ProductSellingModelId = psm.Id
        );
        insert santdaloneProductPsmo;
        
         PricebookEntry santdaloneProductPBE = new PricebookEntry(
            Product2Id = santdaloneProduct.Id,
            Pricebook2Id = standardPBId,
            ProductSellingModelId = psm.Id,
            UnitPrice = 200,
            IsActive = true
        );
        insert santdaloneProductPBE;
    }
    @isTest
    static void RCA_priceBookBatchTestMethod(){
        Test.startTest();
        RCA_PricebookBatchVersion2 batch = new RCA_PricebookBatchVersion2();
		Database.executeBatch(batch,200);
        Test.stopTest();
        Id standardPBId = Test.getStandardPricebookId();
        List<Product2> oldcpqProducts = [select Id from Product2 where Type !='Bundle'];
        List<Product2> newBundleProducts = [select Id from Product2 where Type = 'Bundle'];
        List<PricebookEntry> standardPricebookEntry = [select Id,UnitPrice,Product2Id,Pricebook2Id from PricebookEntry where Pricebook2Id =:standardPBId];
        List<PricebookEntry> newPricebookEntry = [select Id,UnitPrice,Product2Id,Pricebook2Id from PricebookEntry where Pricebook2Id !=:standardPBId];
        //Integer sizeofNewPriceBookEntry = standardPricebookEntry.size()+newBundleProducts.size();
        System.assertEquals(newPricebookEntry.size(),standardPricebookEntry.size(),'PricebookEntry in custom pricebook is not created properly');
    }
}