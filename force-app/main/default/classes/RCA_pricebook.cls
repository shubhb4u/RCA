public class RCA_pricebook {
    //Here Product selling Model we are hardcoding, need to make changes line - 27
    public void createpriceBookEntries(){
        
        //step 0: get the type as bundle from the custom metadata Type instead of hardcoding
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
		String type = config.ProductType__c; //Bundle
        String Rca_standardPricebookId = config.Standard_Price_book__c;
        String Rca_PricebookId =config.RCA_PricebookId__c;
         String psmoId = config.One_Time_Selling_Model__c;
        
        List<Product2> allProductsList = [Select Id,Name,StockKeepingUnit,Type from Product2 where Id = '01tKj00000QXWydIAH'];
        //step 1 : get all the newly created bundle products after product migration
        List<Product2> newBundleProductsList = new List<Product2>();   //[select Id,Name,StockKeepingUnit from Product2 where Type =:type]; // products which are only type bundle after product migration 
        
        List<Product2> oldProductsBeforeMigration = new List<Product2>();//[select Id from Product2 where Type !=:type];   // products before mmigration 
        for(Product2 product :allProductsList){
            if(product.Type==type){
                newBundleProductsList.add(product);
            }
            else{
                oldProductsBeforeMigration.add(product);
            }
        }
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
        
        //The below step is the pre-requsites 
        
        //step 5 : create product selling model option for the newly created products
       
        List<ProductSellingModelOption> psmoListToInsert = new List<ProductSellingModelOption>();
        for(Product2 products :newBundleProductsList){
            ProductSellingModelOption psmo = new ProductSellingModelOption();
            psmo.ProductSellingModelId =psmoId;
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
            entry.Pricebook2Id=Rca_standardPricebookId;
            entry.IsActive=True;
            pricebookEntryToInsert.add(entry);
        }
        Insert pricebookEntryToInsert;
        // craete a pricebok entry into the custom pricebook
        List<PricebookEntry> Rca_pricebookEntryList = new List<PricebookEntry>();
        for(PricebookEntry pricebookEntry : pricebookEntryToInsert){
            PricebookEntry entry = new PricebookEntry();
            entry.IsActive=pricebookEntry.IsActive;
            entry.Product2Id=pricebookEntry.Product2Id;
            entry.Pricebook2Id=Rca_PricebookId;
            entry.ProductSellingModelId=pricebookEntry.ProductSellingModelId;
            entry.UnitPrice =pricebookEntry.UnitPrice;
            Rca_pricebookEntryList.add(entry);
        }
        Insert Rca_pricebookEntryList;

        List<PricebookEntry> oldProductsPriceToInsert = new List<PricebookEntry>();
        List<Id> oldProductsIds = new List<Id>();
        for(Product2 product : oldProductsBeforeMigration){
            oldProductsIds.add(product.Id);
        }
        
        
        List<ProductSellingModelOption> oldProductPsmoList = new List<ProductSellingModelOption>();
        Map<Id,Id> product2ToProductSellingModel = new Map<Id,Id>();
        for(Product2 product :oldProductsBeforeMigration){
            ProductSellingModelOption psmo = new ProductSellingModelOption();
            psmo.Product2Id=product.Id;
            psmo.ProductSellingModelId=psmoId;
            product2ToProductSellingModel.put(product.Id,psmoId);
            oldProductPsmoList.add(psmo);
        }
        insert oldProductPsmoList;
        List<PricebookEntry> oldProductsPrice = [select Id,Pricebook2Id,Product2Id,UnitPrice,ProductSellingModelId,IsDerived,IsActive from PricebookEntry where Product2Id IN :oldProductsIds and Pricebook2Id=:Rca_standardPricebookId];
        for(PricebookEntry entry : oldProductsPrice){
            PricebookEntry pricebookentry = new PricebookEntry();
            pricebookentry.Product2Id=entry.Product2Id;
            pricebookentry.Pricebook2Id= entry.Pricebook2Id;
            pricebookentry.ProductSellingModelId=product2ToProductSellingModel.get(entry.Product2Id);
            pricebookentry.UnitPrice=entry.UnitPrice;
            pricebookentry.IsActive=entry.IsActive;
            oldProductsPriceToInsert.add(pricebookentry);
        }
        if(!oldProductsPriceToInsert.isEmpty()){
            insert oldProductsPriceToInsert;
        }
        List<PricebookEntry> oldproductsCustomPrice = new List<PricebookEntry>();
        for(PricebookEntry entry :oldProductsPriceToInsert){
            PricebookEntry pricebookentry = new PricebookEntry();
            pricebookentry.Product2Id=entry.Product2Id;
            pricebookentry.Pricebook2Id=Rca_PricebookId;
            pricebookentry.ProductSellingModelId=product2ToProductSellingModel.get(entry.Product2Id);
            pricebookentry.UnitPrice=entry.UnitPrice;
            pricebookentry.IsActive=entry.IsActive;
            oldproductsCustomPrice.add(pricebookentry);
        }
        if(!oldproductsCustomPrice.isEmpty()){
            insert oldproductsCustomPrice;
        }
        
    }
}