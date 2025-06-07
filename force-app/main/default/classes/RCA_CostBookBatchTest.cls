@isTest
Private class RCA_CostBookBatchTest {
    @testSetup
    static void testDatasetup(){
        Product2 product = new Product2();
        product.Name = 'Test Product';
        product.StockKeepingUnit = 'TP-01';
        product.ProductCode = 'TP-01';
        insert product;
        Product2 newBundleProduct = new Product2();
        newBundleProduct.Name = 'Bundle Test Product';
        newBundleProduct.StockKeepingUnit = product.StockKeepingUnit+'Bundle';
        newBundleProduct.ProductCode= product.StockKeepingUnit+'Bundle';
        insert newBundleProduct;
        SBQQ__Cost__c cost = new SBQQ__Cost__c();
        cost.SBQQ__Product__c=product.Id;
        cost.SBQQ__Active__c=True;
        cost.SBQQ__UnitCost__c= 100.00;
        insert cost;
    }
    @isTest
    static void RCA_CostBookBatchTestMethod(){
        Test.startTest();
        RCA_CostBookBatch batch = new RCA_CostBookBatch();
        Database.executeBatch(batch,200);
        Test.stopTest();
        Product2 product = [Select Id from Product2 where Name = 'Test Product' limit 1];
        CostBookEntry costbookentry = [select ProductId,Cost from CostBookEntry where ProductId=:product.Id];
        System.assertEquals(100.00,costbookentry.Cost,'Cost Price in CostbookEntry has another value which is not equal as CPQ cost of standalone Product');
        Product2 bundleproduct = [select Id,StockKeepingUnit from Product2 where Name='Bundle Test Product'];
        CostBookEntry costbookentrybundleProduct = [select ProductId,Cost from CostBookEntry where ProductId=:bundleproduct.Id];
        System.assertEquals(costbookentry.Cost,costbookentrybundleProduct.Cost,'Cost Price in CostbookEntry has another value which is not equal as Old CPQ cost of Bundle Product');
    }
}