public class RCA_pricebook {
    //Here Product selling Model we are hardcoding, need to make changes line - 27
    public void createpriceBookEntries(){
        
        //step 0: get the type as bundle from the custom metadata Type instead of hardcoding
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
		String type = config.ProductType__c; //Bundle
        System.debug(type);
        
        //step 1 : get all the newly created bundle products after product migration
        List<Product2> newBundleProductsList = [select Id,Name,StockKeepingUnit from Product2 where Type =:type];
        
        //step 2 : create a map of new products with SKu and its Id SKU ==> Id
        Map<String,Id> newProductSKuToIdMap = new Map<String,Id>();
        for(Product2 product : newBundleProductsList){
            newProductSKuToIdMap.put(product.StockKeepingUnit,product.Id);
        }
        
        //step 3 : Store all the old sku in the oldSKUList
        List<String> oldSKUList = new List<String>(); // list to store all the old products
        for(Product2 product : newBundleProductsList){
            System.debug(product.StockKeepingUnit);
           String oldsku = product.StockKeepingUnit.remove(' - Bundle');
           oldSKUList.add(oldsku);
        }
        
        //step 4: create a map of old sku and its price
        Map<String,Decimal> oldProductSKuToIdMap = new Map<String,Decimal>();
         for(PricebookEntry entry : [select Product2.StockKeepingUnit,UnitPrice from PricebookEntry where Product2.StockKeepingUnit In :oldSKUList]){
            oldProductSKuToIdMap.put(entry.Product2.StockKeepingUnit,entry.UnitPrice);
        }
        
        //The below step is the pre requsites 
        
        //step 5 : create product selling model option for the newly created products
        String psmoId = config.One_Time_Selling_Model__c;
        List<ProductSellingModelOption> psmoListToInsert = new List<ProductSellingModelOption>();
        for(Product2 products :newBundleProductsList){
            ProductSellingModelOption psmo = new ProductSellingModelOption();
            psmo.ProductSellingModelId =psmoId;
            System.debug(psmo.ProductSellingModelId);
            psmo.Product2Id=products.Id;
            psmoListToInsert.add(psmo);
        }
        insert psmoListToInsert;
        
        //step 6 : create pricebook entry for the newly created bundled product
        String pricebookId =config.Standard_Price_book__c;  // To fetch and Store the Standard Pricebook Id
        System.debug(pricebookId);
        Map<Id,Id> ProductIdToProductSellingModelId = new Map<Id,Id>(); // Map to store the ProductId and its ProductsellingModelId   productId==>ProductsellingModelId
        //adding the values to the Map
        for(ProductSellingModelOption psmo : psmoListToInsert){
            ProductIdToProductSellingModelId.put(psmo.Product2Id,psmo.ProductSellingModelId);
        }
        List<PricebookEntry> pricebookEntryToInsert = new List<PricebookEntry>();// List to store the new Instances of Pricebookentries
        
        //Step 7 : create the pricebookentry to insert 
        for(Product2 product : newBundleProductsList){
            PricebookEntry entry = new PricebookEntry();
            String sku = product.StockKeepingUnit.Remove(' - Bundle');
            entry.UnitPrice=oldProductSKuToIdMap.get(sku);
            entry.Product2Id=product.Id;
            entry.ProductSellingModelId =ProductIdToProductSellingModelId.get(product.Id);
            entry.Pricebook2Id=pricebookId;
            entry.IsActive=True;
            pricebookEntryToInsert.add(entry);
        }
        Insert pricebookEntryToInsert;
    }
}