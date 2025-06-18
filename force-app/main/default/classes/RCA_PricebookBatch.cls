global class RCA_PricebookBatch implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();
    private String type;
    private String standardPricebookId;
    private String rcaPricebookId;
    private String psmoId;
    
    // Used across methods
    private Map<String, Id> skuToProductIdMap = new Map<String, Id>();
    private Map<Id, Decimal> productIdToPriceMap = new Map<Id, Decimal>();

    global RCA_PricebookBatch(List<Id> productIds) {
        this.productIds = productIds;
        loadPricingConfig();
    }
    
    global RCA_PricebookBatch() {
        loadPricingConfig();
    }

    private void loadPricingConfig() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        if (config == null) {
            errorMessages.add('Missing Pricing_Method_Config__mdt configuration.');
            return;
        }
    
        this.type = config.ProductType__c;
        this.standardPricebookId = config.Standard_Price_book__c;
        this.rcaPricebookId = config.RCA_PricebookId__c;
        this.psmoId = config.One_Time_Selling_Model__c;
    }
    

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type FROM Product2';
        if (productIds != null && !productIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' WHERE Id IN :productIds');
        }
        System.debug('RCA_PricebookBatch.start - Querying all Product2 records.');
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext bc, List<Product2> allProductsList) {
        

        List<Product2> newBundleProductsList = new List<Product2>();
        List<Product2> oldProductsBeforeMigration = new List<Product2>();
        for (Product2 product : allProductsList) {
            if (product.Type == type) {
                newBundleProductsList.add(product);
            } 
            if(product.Type != type){
                oldProductsBeforeMigration.add(product);
            }
        }

        //Setup old Pricing data map - 
        getSKUToIDmap(allProductsList);

        System.debug('Filtered old products: ' + oldProductsBeforeMigration.size());
        System.debug('Filtered new bundle products: ' + newBundleProductsList.size());

        // OLD Products logic -----------------------------------------------------------
        Map<Id, Id> oldProductToPSMO = upsertPSMOs(oldProductsBeforeMigration, psmoId);
        Map<String, Id> existingKeyToIdMap = getExistingPBEs(oldProductsBeforeMigration, standardPricebookId, rcaPricebookId);

        List<PricebookEntry> oldStdEntries = [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, ProductSellingModelId, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :oldProductsBeforeMigration AND Pricebook2Id = :standardPricebookId
        ];


        //Map of Old CPQ Product Id's and their standard price - 
        for (PricebookEntry entry : oldStdEntries) {
            productIdToPriceMap.put(entry.Product2Id, entry.UnitPrice);
        }

        List<PricebookEntry> cloneStd = clonePBEs(oldStdEntries, oldProductToPSMO, standardPricebookId, existingKeyToIdMap, null, null);
        performDML(cloneStd, 'Upsert: Standard Pricebook Clones', 'upsert');

        List<PricebookEntry> cloneRca = clonePBEs(cloneStd, null, rcaPricebookId, existingKeyToIdMap, null, null);
        performDML(cloneRca, 'Upsert: RCA Pricebook Clones', 'upsert');

        // BUNDLE Products logic ----------------------------------------------------------------
        Map<Id, Id> oldBundleProductToPSMO = upsertPSMOs(newBundleProductsList, psmoId);
        Map<String, Id> existingBundleKeyToIdMap = getExistingPBEs(newBundleProductsList, standardPricebookId, rcaPricebookId);

        //Get all PBE's of products that were duplicated to RCA Bundle products - 
        List<PricebookEntry> oldBundleStdEntries = [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, ProductSellingModelId, IsActive, Product2.StockKeepingUnit
            FROM PricebookEntry
            WHERE Product2Id IN :newBundleProductsList  AND Pricebook2Id = :standardPricebookId
        ];

        List<PricebookEntry> cloneBundleStd = clonePBEs(oldBundleStdEntries, oldBundleProductToPSMO, standardPricebookId, existingBundleKeyToIdMap, 'Bundle', newBundleProductsList);
        performDML(cloneBundleStd, 'Upsert: Bundle Std PBEs', 'upsert');

        List<PricebookEntry> cloneBundleRca = clonePBEs(cloneBundleStd, null, rcaPricebookId, existingBundleKeyToIdMap, null, null);
        performDML(cloneBundleRca, 'Upsert: Bundle RCA PBEs', 'upsert');
    }

    private Map<Id, Id> upsertPSMOs(List<Product2> products, String psmoId) {
        Map<Id, Id> productToPSMOMap = new Map<Id, Id>();
        if (products.isEmpty()) return productToPSMOMap;
        System.debug('upsertPSMOs - Products: ' + products.size() + ', PSMO ID: ' + psmoId);

        Map<Id, ProductSellingModelOption> existingPSMOs = new Map<Id, ProductSellingModelOption>();
        for (ProductSellingModelOption psmo : [
            SELECT Id, Product2Id FROM ProductSellingModelOption
            WHERE Product2Id IN :products AND ProductSellingModelId = :psmoId
        ]) {
            existingPSMOs.put(psmo.Product2Id, psmo);
        }

        List<ProductSellingModelOption> upsertList = new List<ProductSellingModelOption>();
        for (Product2 product : products) {
            ProductSellingModelOption option = new ProductSellingModelOption(
                Product2Id = product.Id,
                ProductSellingModelId = psmoId
            );
            if (existingPSMOs.containsKey(product.Id)) {
                option.Id = existingPSMOs.get(product.Id).Id;
            }
            upsertList.add(option);
            productToPSMOMap.put(product.Id, psmoId);
        }

        performDML(upsertList, 'Upsert: ProductSellingModelOptions', 'upsert');
        return productToPSMOMap;
    }

    private Map<String, Id> getExistingPBEs(List<Product2> products, String standardPricebookId, String rcaPricebookId) {
        System.debug('getExistingPBEs - Products: ' + products.size());

        Map<String, Id> keyToIdMap = new Map<String, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :products AND Pricebook2Id IN :new List<Id>{standardPricebookId, rcaPricebookId}
        ]) {
            String key = pbe.Product2Id + '-' + pbe.Pricebook2Id + '-' + this.psmoId;
            keyToIdMap.put(key, pbe.Id);
        }
        return keyToIdMap;
    }

    private List<PricebookEntry> clonePBEs(List<PricebookEntry> sourcePBEs, Map<Id, Id> productToPSMO,
        String targetPricebookId, Map<String, Id> existingKeyToIdMap, String productType,
        List<Product2> newBundleProductsList) {
            
        System.debug('clonePBEs - Source PBEs: ' + sourcePBEs.size() + ', Target PB: ' + targetPricebookId + ', Type: ' + productType);

        List<PricebookEntry> result = new List<PricebookEntry>();

        if (productType == 'Bundle') {
        // Create new Std and RCA PBEs for new Bundle Products using prices from original products
            for (Product2 pd : newBundleProductsList) {
                String sku = pd.StockKeepingUnit;
                if (sku != null && sku.endsWith(' - Bundle')) {
                    String derivedSKU = sku.replace(' - Bundle', '');

                    Id originalProdId = skuToProductIdMap.get(derivedSKU);
                    Decimal price = productIdToPriceMap.get(originalProdId);

                    if (originalProdId == null || price == null) {
                        errorMessages.add('Missing original product or price for Bundle SKU: ' + sku);
                        continue;
                    }

                    Id modelId = productToPSMO != null ? productToPSMO.get(pd.Id) : this.psmoId;
                    String key = pd.Id + '-' + targetPricebookId + '-' + modelId;


                    PricebookEntry newBundlePBE = new PricebookEntry(
                        Product2Id = pd.Id,
                        Pricebook2Id = targetPricebookId,
                        ProductSellingModelId = psmoId,
                        UnitPrice = price,
                        IsActive = true
                    );

                    if (existingKeyToIdMap.containsKey(key)) {
                        newBundlePBE.Id = existingKeyToIdMap.get(key);
                    }

                    result.add(newBundlePBE);
                }
            }

        } else {
            // Preload existing Standard PBEs into a Set for validation
            Set<String> stdKeys = new Set<String>();
            for (PricebookEntry stdPBE : [SELECT Product2Id, ProductSellingModelId
                                           FROM PricebookEntry
                                           WHERE Pricebook2.Id = :standardPricebookId]) {
                stdKeys.add(stdPBE.Product2Id + '-' + stdPBE.ProductSellingModelId);
            }
        
            for (PricebookEntry entry : sourcePBEs) {
                Id modelId = productToPSMO != null ? productToPSMO.get(entry.Product2Id) : this.psmoId;
                String key = entry.Product2Id + '-' + targetPricebookId + '-' + modelId;
        
                // Check if corresponding Standard PBE exists
                String stdKey = entry.Product2Id + '-' + modelId;
                if (!stdKeys.contains(stdKey)) {
                    errorMessages.add('Skipping RCA PBE: Standard PBE missing for Product2Id: ' + entry.Product2Id + ', PSMO: ' + modelId);
                    continue;
                }
        
                PricebookEntry newPBE = new PricebookEntry(
                    Product2Id = entry.Product2Id,
                    Pricebook2Id = targetPricebookId,
                    ProductSellingModelId = psmoId,
                    UnitPrice = entry.UnitPrice,
                    IsActive = entry.IsActive
                );
        
                if (existingKeyToIdMap.containsKey(key)) {
                    newPBE.Id = existingKeyToIdMap.get(key);
                }
        
                result.add(newPBE);
            }
        }
        return result;
    }
        


    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorEmail();
        } else {
            System.debug('RCA_PricebookBatch completed successfully with no errors.');
        }
    }

    private void getSKUToIDmap(List<Product2> oldProducts){

        //Map of old CPQ products SKU's and their Id - 
        for (Product2 p : oldProducts) {
            if (String.isNotBlank(p.StockKeepingUnit)) {
                String origSKU = p.StockKeepingUnit.replace(' - Bundle', '');
                List<Product2> oldProd = [Select id, StockKeepingUnit from product2 where stockkeepingUnit =: origSKU LIMIT 1];
                skuToProductIdMap.put(origSKU, oldProd[0].Id);

                List<PricebookEntry> oldStdEntries = [SELECT Id, Pricebook2Id, Product2Id, UnitPrice, ProductSellingModelId, IsActive FROM PricebookEntry WHERE Product2.stockkeepingUnit =: origSKU AND Pricebook2Id = :standardPricebookId
                ];

                //Map of Old CPQ Product Id's and their standard price - 
                for (PricebookEntry entry : oldStdEntries) {
                    productIdToPriceMap.put(entry.Product2Id, entry.UnitPrice);
                }
            }
        }
            
    }

    private void performDML(List<SObject> dmlList, String context, String option) {
        if (dmlList.isEmpty()) return;
        System.debug('Performing DML - Context: ' + context + ', Type: ' + option + ', Records: ' + dmlList.size());

        Set<Id> seenIds = new Set<Id>();
        List<SObject> cleanedList = new List<SObject>();

        for (SObject sObj : dmlList) {
            if (sObj.Id == null || seenIds.add(sObj.Id)) {
                cleanedList.add(sObj);
            }
        }
    
        try {
            if (option == 'insert') {
                List<Database.SaveResult> results = Database.insert(cleanedList, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } else if (option == 'upsert') {
                List<Database.UpsertResult> results = Database.upsert(cleanedList, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } else if (option == 'update') {
                List<Database.SaveResult> results = Database.update(cleanedList, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } else {
                errorMessages.add(context + ' failed: Unsupported DML operation "' + option + '"');
            }
    
        } catch (Exception e) {
            errorMessages.add('Exception during ' + context + ': ' + e.getMessage());
        }
    }


    

    private void sendErrorEmail() {
        String adminEmail = 'Shubham.m@etg.digital';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { adminEmail });
        mail.setSubject('RCA_PricebookBatch Errors');
        mail.setPlainTextBody('The batch encountered the following errors:\n\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}
