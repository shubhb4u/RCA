@isTest
private class RCA_DerivedPricingBatchTest {
    @testSetup
    static void testDatasetup(){
        Id standardPBId = Test.getStandardPricebookId();
        
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.IsActive=True;
        product.StockKeepingUnit = 'TP-01';
        product.ProductCode = 'TP-01';
        product.SBQQ__PricingMethod__c='Percent Of Total';
        product.SBQQ__SubscriptionBase__c = 'Net';
        product.SBQQ__SubscriptionPercent__c= 10.00;
        insert product;
        
        Product2 newbundleProduct= new Product2();
        newbundleProduct.Name = 'Bundle Test Product';
        newbundleProduct.IsActive=True;
        newbundleProduct.StockKeepingUnit = product.StockKeepingUnit+'Bundle';
        newbundleProduct.Type='Bundle';
        insert newbundleProduct;
        
        
        
        ProductSellingModel psm = new ProductSellingModel();
        psm.Name = 'OneTime';
        psm.SellingModelType = 'OneTime';
        psm.Status = 'Active';
        insert psm;
        
        ProductSellingModelOption  psmo = new ProductSellingModelOption();
        psmo.Product2Id = product.Id;
        psmo.ProductSellingModelId=psm.Id;
        insert psmo;
        
       // Pricebook2 pricebook = new Pricebook2();
       // pricebook.Name='Standard price book';
       // pricebook.IsActive=True;
        //pricebook.IsStandard=True;
        //insert pricebook;
        
        PricebookEntry pricebookentry = new PricebookEntry();
        pricebookentry.Product2Id=product.Id;
        pricebookentry.Pricebook2Id=standardPBId;
        pricebookentry.ProductSellingModelId=psm.Id;
        pricebookentry.UnitPrice = 100.00;
        pricebookentry.IsActive = True;
        insert pricebookentry;
        
    }
    @isTest
    static void RCA_DerivedPricingBatchMethod(){
        Test.startTest();
        RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch();
        Database.executeBatch(batch,200);
        Test.stopTest();
        Product2 product = [select Id,stockKeepingUnit from Product2 where stockKeepingUnit = 'TP-01'];
        PricebookEntry pricebookentry = [select Id,IsDerived,UnitPrice From PricebookEntry where Product2Id =:product.Id];
        System.assertEquals(pricebookentry.IsDerived,True,'successfully inserted');
        System.assertEquals(pricebookentry.UnitPrice,0.00,'successfully inserted');
        String sku = product.StockKeepingUnit+'Bundle';
        Product2 newbundleproduct = [select Id from Product2 where stockKeepingUnit =:sku];
        PricebookEntry newbundlepricebookentry = [select Id,IsDerived,UnitPrice From PricebookEntry where Product2Id =:newbundleproduct.Id];
        System.assertEquals(newbundlepricebookentry.IsDerived,True,'PriceBook is not created with isDerived As True');
        System.assertEquals(newbundlepricebookentry.UnitPrice,0.00,'Unit Price must be Zero but got another value');
    }
    
}