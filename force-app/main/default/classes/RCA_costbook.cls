public class RCA_costbook {
    public void createCostBookEntries() {
        //Step 1: get the Id of the Standard Costbook from the custom metadata Type instead of hardcoding
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal'); 
        List<SBQQ__Cost__c> costRecords = [SELECT SBQQ__Product__c, SBQQ__UnitCost__c FROM SBQQ__Cost__c];//fetches all the cost prices of the products
        List<CostBookEntry> costBookEntries = new List<CostBookEntry>();  // List to store the costbookEntry
        //Step 2: get all the products Id's which has cost price and store them in productIds List
        List<Id> productIds = new List<Id>();
        for(SBQQ__Cost__c cost : costRecords){
            productIds.add(cost.SBQQ__Product__c);
        }
        
        //Step 3: create a Map of ProductId and it Cost Price    productId ==> CostPrice
        Map<Id,Decimal> ProductToPriceMap = new Map<Id,Decimal>();
        for(SBQQ__Cost__c c :costRecords){
            ProductToPriceMap.put(c.SBQQ__Product__c,c.SBQQ__UnitCost__c);
        }
        
        
        //step 4 : create a Map of SKU and its Id  SKU ==> ProductId        
        Map<String,Id> ProductSKuToId = new Map<String,Id>();// stores product id and costprice
        for(Product2 product : [select Id,StockKeepingUnit from Product2 where Id IN :productIds]){
            ProductSKuToId.put(product.StockKeepingUnit,product.Id);
        }
        
        
        //step 5 : Create CostBookEntry for all the products after migration but not the newly created bundle product
        String costBookId=config.CostBook__c;
        for (SBQQ__Cost__c cost : costRecords) {
            CostBookEntry entry = new CostBookEntry();
            entry.CostBookId = costBookId; // Replace with dynamic value if needed
            System.debug(entry.CostBookId);
            entry.ProductId = cost.SBQQ__Product__c;
            entry.Cost = cost.SBQQ__UnitCost__c;
            entry.EffectiveFrom = DateTime.now();
            costBookEntries.add(entry);
        }
        
        //step 6 : Create a List of SKU to store newly created products ad type bundle as we follow convention (oldSKU+' - bundle')
        List<String> newSKUList = new List<String>();
        for(Product2 product : [select StockKeepingUnit from Product2 where Id In :productIds]){
            String newSku = product.StockKeepingUnit+'Bundle';
            newSKUList.add(newSku);
        }
        //step 7 : Create a Map of new ProductId and Its SKU
        Map<String,Id> newProductSkuToId = new Map<String,Id>();
        List<Product2> newlycreatedProduct = [select Id,Name,StockKeepingUnit from Product2 where StockKeepingUnit In : newSKUList];
        for(Product2 product : newlycreatedProduct){
            newProductSkuToId.put(product.StockKeepingUnit,product.Id);
        }
        //step 8 : create cost book entry for the newly created bundle products
        for(Product2 product : newlycreatedProduct){
            CostBookEntry entry = new CostBookEntry();
            entry.CostBookId = costBookId;
            entry.ProductId=product.Id;
            String sku = product.StockKeepingUnit.remove('Bundle');
            Id oldproductId = ProductSKuToId.get(sku);
            entry.Cost=ProductToPriceMap.get(oldproductId);
            entry.EffectiveFrom = DateTime.now();
            costBookEntries.add(entry);
        }
        
        //insert all the costbook entries created
        if (!costBookEntries.isEmpty()) {
            insert costBookEntries;
        }
    }
}