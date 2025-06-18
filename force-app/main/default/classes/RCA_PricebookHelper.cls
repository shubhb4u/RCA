public class RCA_PricebookHelper {
    public List<String> errorMessages = new List<String>();
    
    public void processProducts(List<Product2> products) {
        System.debug('### Execute called with ' + products.size() + ' products');

        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        if (config == null) {
            errorMessages.add('Missing Pricing_Method_Config__mdt configuration.');
            System.debug('### Missing configuration: PercentOfTotal');
            return;
        }

        String type = config.ProductType__c;
        String stdPB = config.Standard_Price_book__c;
        String rcaPB = config.RCA_PricebookId__c;
        String psmoId = config.One_Time_Selling_Model__c;

        System.debug('### Config values: Type=' + type + ', StdPB=' + stdPB + ', RCAPB=' + rcaPB + ', PSMO=' + psmoId);

        if (String.isBlank(stdPB) || String.isBlank(rcaPB) || String.isBlank(psmoId)) {
            errorMessages.add('Configuration values are missing in metadata.');
            System.debug('### Configuration missing required values.');
            return;
        }

        List<Product2> bundles = new List<Product2>();
        List<Product2> oldProducts = new List<Product2>();
        for (Product2 p : products) {
            if (p.Type == type) {
                bundles.add(p);
            } else {
                oldProducts.add(p);
            }
        }

        System.debug('### Old Products count: ' + oldProducts.size() + ', Bundles count: ' + bundles.size());

        Map<Id, Id> oldProdToPSMO = upsertPSMOs(oldProducts, psmoId, 'Old');
        List<PricebookEntry> oldStdPBEs = getPBEs(stdPB);
        Map<String, Id> existingPBEs = getExistingPBEMap(oldProducts, new List<Id>{stdPB, rcaPB});
        Map<String, Id> skuToProdId = getSKUMap(oldProducts, bundles);
        Map<Id, Decimal> prodToPrice = getPriceMap(oldStdPBEs);

        System.debug('### Cloning STD PBEs for old products');
        List<PricebookEntry> stdPBEs = clonePBEs(oldStdPBEs, stdPB, psmoId, existingPBEs);
        performDML(stdPBEs, 'Upsert: Standard PBEs (Old)', 'upsert');

        System.debug('### Cloning RCA PBEs for old products');
        List<PricebookEntry> rcaPBEs = clonePBEs(stdPBEs, rcaPB, psmoId, existingPBEs);
        performDML(rcaPBEs, 'Upsert: RCA PBEs (Old)', 'upsert');

        System.debug('### Upserting PSMOs for bundles');
        upsertPSMOs(bundles, psmoId, 'Bundle');
        Map<String, Id> existingBundlePBEs = getExistingPBEMap(bundles, new List<Id>{stdPB, rcaPB});

        System.debug('### Creating STD PBEs for bundles');
        List<PricebookEntry> bundleStd = createBundlePBEs(bundles, stdPB, psmoId, skuToProdId, prodToPrice, existingBundlePBEs);
        performDML(bundleStd, 'Upsert: Bundle PBEs (STD)', 'upsert');

        System.debug('### Cloning RCA PBEs for bundles');
        List<PricebookEntry> bundleRCA = clonePBEs(bundleStd, rcaPB, psmoId, existingBundlePBEs);
        performDML(bundleRCA, 'Upsert: Bundle PBEs (RCA)', 'upsert');
    }

    // All the helper methods remain exactly the same as in your original class
    private Map<Id, Id> upsertPSMOs(List<Product2> products, String psmoId, String label) {
        System.debug('### Upserting PSMOs for ' + label + ' products: ' + products.size());
        Map<Id, Id> result = new Map<Id, Id>();
        if (products.isEmpty()) return result;

        Map<Id, ProductSellingModelOption> existing = new Map<Id, ProductSellingModelOption>();
        for (ProductSellingModelOption psmo : [
            SELECT Id, Product2Id FROM ProductSellingModelOption
            WHERE Product2Id IN :products AND ProductSellingModelId = :psmoId
        ]) {
            existing.put(psmo.Product2Id, psmo);
        }

        List<ProductSellingModelOption> toUpsert = new List<ProductSellingModelOption>();
        for (Product2 p : products) {
            ProductSellingModelOption opt = new ProductSellingModelOption(
                Product2Id = p.Id,
                ProductSellingModelId = psmoId
            );
            if (existing.containsKey(p.Id)) {
                opt.Id = existing.get(p.Id).Id;
            }
            result.put(p.Id, psmoId);
            toUpsert.add(opt);
        }

        System.debug('### PSMOs to upsert for ' + label + ': ' + toUpsert.size());
        performDML(toUpsert, 'Upsert: ' + label + ' PSMOs', 'upsert');
        return result;
    }

    private List<PricebookEntry> getPBEs(String pbId) {
        System.debug('### Fetching PBEs for Pricebook: ' + pbId );
        return [SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId, IsActive
                FROM PricebookEntry WHERE Pricebook2Id = :pbId];
    }

    private Map<String, Id> getExistingPBEMap(List<Product2> products, List<Id> pbIds) {
        System.debug('### Fetching existing PBE Map');
        Map<String, Id> existingMap = new Map<String, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice
            FROM PricebookEntry WHERE Product2Id IN :products AND Pricebook2Id IN :pbIds
        ]) {
            String key = pbe.Product2Id + '-' + pbe.Pricebook2Id + '-' + pbe.ProductSellingModelId;
            existingMap.put(key, pbe.Id);
        }
        return existingMap;
    }

    private Map<String, Id> getSKUMap(List<Product2> products, List<Product2> bundleProd) {
        Map<String, Id> SKUMap = new Map<String, Id>();

        if(products!=null && !products.isEmpty()){
            for (Product2 p : products) {
                if (String.isNotBlank(p.StockKeepingUnit)) {
                    SKUMap.put(p.StockKeepingUnit, p.Id);
                }
            }
            System.debug('### SKU to Product2Id map created with size: ' + SKUMap.size());
        }else{
            if(bundleProd!=null || !bundleProd.isEmpty()){
                for (Product2 p : bundleProd) {
                    if (String.isNotBlank(p.StockKeepingUnit)) {
                        String origSKU = p.StockKeepingUnit.replace(' - Bundle', '');
                        List<Product2> oldProd = [Select Id, StockKeepingUnit from Product2 where StockKeepingUnit =: origSKU LIMIT 1];
                        SKUMap.put(oldProd[0].StockKeepingUnit, oldProd[0].Id);
                    }
                    
                }
            System.debug('### Bundle SKU to Product2Id map created with size: ' + SKUMap.size());
            }
        }
        
        return SKUMap;
    }

    private Map<Id, Decimal> getPriceMap(List<PricebookEntry> entries) {
        Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
        for (PricebookEntry e : entries) {
            priceMap.put(e.Product2Id, e.UnitPrice);
        }
        System.debug('### Price map created with size: ' + priceMap.size());
        return priceMap;
    }

    private List<PricebookEntry> clonePBEs(List<PricebookEntry> entries, String pbId, String psmoId, Map<String, Id> existingMap) {
        List<PricebookEntry> cloneList = new List<PricebookEntry>();
        for (PricebookEntry e : entries) {
            String key = e.Product2Id + '-' + pbId + '-' + psmoId;
            PricebookEntry clone = new PricebookEntry(
                Product2Id = e.Product2Id,
                Pricebook2Id = pbId,
                ProductSellingModelId = psmoId,
                UnitPrice = e.UnitPrice,
                IsActive = e.IsActive
            );
            if (existingMap.containsKey(key)) {
                clone.Id = existingMap.get(key);
            }
            cloneList.add(clone);
        }
        System.debug('### Cloned PBEs count: ' + cloneList.size());
        return cloneList;
    }

    private List<PricebookEntry> createBundlePBEs(
        List<Product2> bundles, String pbId, String psmoId,
        Map<String, Id> skuToProd, Map<Id, Decimal> prodToPrice,
        Map<String, Id> existingMap
    ) {
        List<PricebookEntry> bundleList = new List<PricebookEntry>();
        for (Product2 p : bundles) {
            if (p.StockKeepingUnit == null || !p.StockKeepingUnit.endsWith(' - Bundle')) continue;

            String baseSKU = p.StockKeepingUnit.replace(' - Bundle', '');
            Id originalId = skuToProd.get(baseSKU);
            Decimal price = prodToPrice.get(originalId);

            if (originalId == null || price == null) {
                errorMessages.add('Missing base SKU or price for bundle: ' + p.StockKeepingUnit);
                System.debug('### Skipped bundle due to missing base SKU or price: ' + p.StockKeepingUnit);
                continue;
            }

            String key = p.Id + '-' + pbId + '-' + psmoId;
            PricebookEntry pbe = new PricebookEntry(
                Product2Id = p.Id,
                Pricebook2Id = pbId,
                ProductSellingModelId = psmoId,
                UnitPrice = price,
                IsActive = true
            );
            if (existingMap.containsKey(key)) {
                pbe.Id = existingMap.get(key);
            }
            bundleList.add(pbe);
        }
        System.debug('### Created bundle PBEs: ' + bundleList.size());
        return bundleList;
    }

    private void performDML(List<SObject> dmlList, String context, String option) {
        System.debug('### Performing ' + option + ' DML for context: ' + context + ' | Records: ' + dmlList.size());
        if (dmlList.isEmpty()) return;

        try {
            if (option == 'insert') {
                Database.SaveResult[] results = Database.insert(dmlList, false);
                processResults(results, context);
            } else if (option == 'update') {
                Database.SaveResult[] results = Database.update(dmlList, false);
                processResults(results, context);
            } else if (option == 'upsert') {
                Database.UpsertResult[] results = Database.upsert(dmlList, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                        System.debug('### ERROR [' + context + '] index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } else {
                errorMessages.add(context + ' failed: Unsupported DML operation "' + option + '"');
                System.debug('### ERROR: Unsupported DML operation: ' + option);
            }
        } catch (Exception e) {
            errorMessages.add('Exception in ' + context + ': ' + e.getMessage());
            System.debug('### EXCEPTION in ' + context + ': ' + e.getMessage());
        }
    }

    private void processResults(Database.SaveResult[] results, String context) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                String msg = context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage();
                errorMessages.add(msg);
                System.debug('### ERROR: ' + msg);
            }
        }
    }
}