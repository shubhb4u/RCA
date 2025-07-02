public class RCA_PricebookHelper {

    @TestVisible private static Boolean forceExceptionInTest = false;

    public void processProducts(List<Product2> products) {

        if (Test.isRunningTest() && forceExceptionInTest) {
             throw new AuraHandledException('Simulated exception for test coverage');
        }

        String type = 'Bundle';

        // Safe SOQL for Standard Price Book
        Id stdPB;
        List<Pricebook2> stdPBList = [SELECT Id FROM PriceBook2 WHERE Name = 'Standard Price Book' LIMIT 1];
        if (!stdPBList.isEmpty()) {
            stdPB = stdPBList[0].Id;
        }

        // Safe SOQL for RCA Price Book
        Id rcaPB;
        List<Pricebook2> rcaPBList = [SELECT Id FROM PriceBook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        if (!rcaPBList.isEmpty()) {
            rcaPB = rcaPBList[0].Id;
        }

        // Safe SOQL for Product Selling Model
        Id psmoId;
        List<ProductSellingModel> psmoList = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time' LIMIT 1];
        if (!psmoList.isEmpty()) {
            psmoId = psmoList[0].Id;
        }

        // Now this condition will be covered safely
        if (String.isBlank(stdPB) || String.isBlank(rcaPB) || String.isBlank(psmoId)) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PricebookBatchVersion2',
                'processProducts',
                'Config',
                null,
                'Missing config values: stdPB=' + stdPB + ', rcaPB=' + rcaPB + ', psmoId=' + psmoId
            );
            return;
        }
    
        List<Product2> bundles = new List<Product2>();
        List<Product2> oldProducts = new List<Product2>();
        //Create PSMOs for all products as it is Mandate to create PBE's
        Map<Id, Id> allProdToPSMO = upsertPSMOs(products, psmoId, 'All');
    
        for (Product2 p : products) {
            if (p.Type == type) {
                bundles.add(p);
            } else {
                oldProducts.add(p);
            }
        }
    
        // Shared SKU map from all input products
        Map<String, Id> skuToProdId = getSKUMap(products);
    
        // If normal products exist
        if (!oldProducts.isEmpty()) {
            List<Id> oldProductIds = new List<Id>();
            for (Product2 p : oldProducts) oldProductIds.add(p.Id);
    
            List<PricebookEntry> oldStdPBEs = getPBEs(stdPB, oldProductIds);
            Map<String, Id> existingPBEs = getExistingPBEMap(oldProducts, new List<Id>{stdPB, rcaPB});
            Map<Id, Decimal> prodToPrice = getPriceMap(oldStdPBEs);
    
            List<PricebookEntry> stdPBEs = clonePBEs(oldStdPBEs, stdPB, psmoId, existingPBEs);
            performDML(stdPBEs, 'Upsert: Standard PBEs (Old)', 'upsert');
    
            List<PricebookEntry> rcaPBEs = clonePBEs(stdPBEs, rcaPB, psmoId, existingPBEs);
            performDML(rcaPBEs, 'Upsert: RCA PBEs (Old)', 'upsert');
        }
    
        // If bundle products exist
        if (!bundles.isEmpty()) {
            Map<String, Id> existingBundlePBEs = getExistingPBEMap(bundles, new List<Id>{stdPB, rcaPB});
    
            // For bundles, we still need original prices from old products
            // So we fetch them only if not already fetched
            Map<Id, Decimal> prodToPrice;
            if (oldProducts.isEmpty()) {
                List<Product2> baseProds = new List<Product2>();
                for (Product2 p : bundles) {
                    if (p.StockKeepingUnit != null && p.StockKeepingUnit.endsWith(' - Bundle')) {
                        String baseSKU = p.StockKeepingUnit.replace(' - Bundle', '');
                        Id baseId = skuToProdId.get(baseSKU);
                        if (baseId != null) {
                            baseProds.add(new Product2(Id = baseId));
                        }
                    }
                }
                List<Id> baseIds = new List<Id>();
                for (Product2 p : baseProds) baseIds.add(p.Id);
                List<PricebookEntry> basePBEs = getPBEs(stdPB, baseIds);
                prodToPrice = getPriceMap(basePBEs);
            } else {
                // Reuse previously built price map
                prodToPrice = getPriceMap(getPBEs(stdPB, new List<Id>(skuToProdId.values())));
            }
    
            List<PricebookEntry> bundleStd = createBundlePBEs(bundles, stdPB, psmoId, skuToProdId, prodToPrice, existingBundlePBEs);
            performDML(bundleStd, 'Upsert: Bundle PBEs (STD)', 'upsert');
    
            List<PricebookEntry> bundleRCA = clonePBEs(bundleStd, rcaPB, psmoId, existingBundlePBEs);
            performDML(bundleRCA, 'Upsert: Bundle PBEs (RCA)', 'upsert');
        }
    }
    

    public Map<Id, Id> upsertPSMOs(List<Product2> products, String psmoId, String label) {
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

        performDML(toUpsert, 'Upsert: ' + label + ' PSMOs', 'upsert');
        return result;
    }

    public List<PricebookEntry> getPBEs(String pbId, List<Id> productIds) {
        return [
            SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId, IsActive
            FROM PricebookEntry
            WHERE Pricebook2Id = :pbId AND Product2Id IN :productIds
        ];
    }

    public Map<String, Id> getExistingPBEMap(List<Product2> products, List<Id> pbIds) {
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

    public Map<String, Id> getSKUMap(List<Product2> products) {
        Map<String, Id> skuMap = new Map<String, Id>();
        for (Product2 p : products) {
            skuMap.put(p.StockKeepingUnit, p.Id);
        }
        return skuMap;
    }

    public Map<Id, Decimal> getPriceMap(List<PricebookEntry> entries) {
        Map<Id, Decimal> priceMap = new Map<Id, Decimal>();
        for (PricebookEntry e : entries) {
            priceMap.put(e.Product2Id, e.UnitPrice);
        }
        return priceMap;
    }

    public List<PricebookEntry> clonePBEs(List<PricebookEntry> entries, String pbId, String psmoId, Map<String, Id> existingMap) {
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
        return cloneList;
    }

    public List<PricebookEntry> createBundlePBEs(
        List<Product2> bundles,
        String pbId,
        String psmoId,
        Map<String, Id> skuToProd,
        Map<Id, Decimal> prodToPrice,
        Map<String, Id> existingMap
    ) {
        List<PricebookEntry> bundleList = new List<PricebookEntry>();
        for (Product2 p : bundles) {
            if (p.StockKeepingUnit == null || !p.StockKeepingUnit.endsWith(' - Bundle')) continue;

            String baseSKU = p.StockKeepingUnit.replace(' - Bundle', '');
            Id originalId = skuToProd.get(baseSKU);
            Decimal price = prodToPrice.get(originalId);

            if (originalId == null || price == null) {
                RCA_BatchExceptionLogger.logExceptions(
                    'RCA_PricebookBatchVersion2',
                    'createBundlePBEs',
                    'Product2',
                    null,
                    'Missing base SKU or price for bundle: ' + p.StockKeepingUnit
                );
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

        return bundleList;
    }

    public void performDML(List<SObject> dmlList, String context, String option) {
        if (dmlList.isEmpty()) return;

        try {
            if (option == 'upsert') {
                Database.UpsertResult[] results = Database.upsert(dmlList, false);
                processUpsertResults(results, context, dmlList);
            } else {
                RCA_BatchExceptionLogger.logExceptions('RCA_PricebookBatchVersion2', context, 'UnknownDML', null, 'Unsupported DML operation: ' + option);
            }
        } catch (Exception e) {
            RCA_BatchExceptionLogger.logExceptions('RCA_PricebookBatchVersion2', context, 'DML_Exception', null, e.getMessage());
        }
    }

    public void processUpsertResults(Database.UpsertResult[] results, String context, List<SObject> records) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                RCA_BatchExceptionLogger.logExceptions(
                    'RCA_PricebookBatchVersion2',
                    context,
                    records[i].getSObjectType().getDescribe().getName(),
                    results[i].getErrors(),
                    JSON.serialize(records[i])
                );
            }
        }
    }
}
