global class RCA_PricebookBatch implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();

    global RCA_PricebookBatch(List<Id> productIds) {
        this.productIds = productIds;
    }

    global RCA_PricebookBatch() {}

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type FROM Product2';
        return Database.getQueryLocator(
            productIds != null && !productIds.isEmpty() 
            ? baseQuery + ' WHERE Id IN :productIds' 
            : baseQuery
        );
    }

    global void execute(Database.BatchableContext bc, List<Product2> products) {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        if (config == null) {
            errorMessages.add('Missing Pricing_Method_Config__mdt configuration.');
            return;
        }

        String type = config.ProductType__c;
        String stdPB = config.Standard_Price_book__c;
        String rcaPB = config.RCA_PricebookId__c;
        String psmoId = config.One_Time_Selling_Model__c;

        if (String.isBlank(stdPB) || String.isBlank(rcaPB) || String.isBlank(psmoId)) {
            errorMessages.add('Configuration values are missing in metadata.');
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

        Map<Id, Id> oldProdToPSMO = upsertPSMOs(oldProducts, psmoId, 'Old');
        List<PricebookEntry> oldStdPBEs = getPBEs(oldProducts, stdPB);
        Map<String, Id> existingPBEs = getExistingPBEMap(oldProducts, new List<Id>{stdPB, rcaPB});
        Map<String, Id> skuToProdId = getSKUMap(oldProducts);
        Map<Id, Decimal> prodToPrice = getPriceMap(oldStdPBEs);

        List<PricebookEntry> stdPBEs = clonePBEs(oldStdPBEs, stdPB, psmoId, existingPBEs);
        performDML(stdPBEs, 'Upsert: Standard PBEs (Old)', 'upsert');

        List<PricebookEntry> rcaPBEs = clonePBEs(stdPBEs, rcaPB, psmoId, existingPBEs);
        performDML(rcaPBEs, 'Upsert: RCA PBEs (Old)', 'upsert');

        upsertPSMOs(bundles, psmoId, 'Bundle');
        Map<String, Id> existingBundlePBEs = getExistingPBEMap(bundles, new List<Id>{stdPB, rcaPB});
        List<PricebookEntry> bundleStd = createBundlePBEs(bundles, stdPB, psmoId, skuToProdId, prodToPrice, existingBundlePBEs);
        performDML(bundleStd, 'Upsert: Bundle PBEs (STD)', 'upsert');

        List<PricebookEntry> bundleRCA = clonePBEs(bundleStd, rcaPB, psmoId, existingBundlePBEs);
        performDML(bundleRCA, 'Upsert: Bundle PBEs (RCA)', 'upsert');
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorEmail();
        } else {
            System.debug('RCA_PricebookBatchVersion2 completed with no errors.');
        }
    }

    private Map<Id, Id> upsertPSMOs(List<Product2> products, String psmoId, String label) {
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

    private List<PricebookEntry> getPBEs(List<Product2> products, String pbId) {
        return [SELECT Id, Product2Id, Pricebook2Id, UnitPrice, ProductSellingModelId, IsActive
                FROM PricebookEntry WHERE Product2Id IN :products AND Pricebook2Id = :pbId];
    }

    private Map<String, Id> getExistingPBEMap(List<Product2> products, List<Id> pbIds) {
        Map<String, Id> resultMap = new Map<String, Id>();
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice
            FROM PricebookEntry WHERE Product2Id IN :products AND Pricebook2Id IN :pbIds
        ]) {
            String key = pbe.Product2Id + '-' + pbe.Pricebook2Id + '-' + pbe.ProductSellingModelId + '-' + pbe.UnitPrice;
            resultMap.put(key, pbe.Id);
        }
        return resultMap;
    }

    private Map<String, Id> getSKUMap(List<Product2> products) {
        Map<String, Id> resultMap = new Map<String, Id>();
        for (Product2 p : products) {
            if (String.isNotBlank(p.StockKeepingUnit)) {
                resultMap.put(p.StockKeepingUnit, p.Id);
            }
        }
        return resultMap;
    }

    private Map<Id, Decimal> getPriceMap(List<PricebookEntry> entries) {
        Map<Id, Decimal> resultMap = new Map<Id, Decimal>();
        for (PricebookEntry e : entries) {
            resultMap.put(e.Product2Id, e.UnitPrice);
        }
        return resultMap;
    }

    private List<PricebookEntry> clonePBEs(List<PricebookEntry> entries, String pbId, String psmoId, Map<String, Id> existingMap) {
        List<PricebookEntry> resultList = new List<PricebookEntry>();
        for (PricebookEntry e : entries) {
            String key = e.Product2Id + '-' + pbId + '-' + psmoId + '-' + e.UnitPrice;
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
            resultList.add(clone);
        }
        return resultList;
    }

    private List<PricebookEntry> createBundlePBEs(
        List<Product2> bundles, String pbId, String psmoId,
        Map<String, Id> skuToProd, Map<Id, Decimal> prodToPrice,
        Map<String, Id> existingMap
    ) {
        List<PricebookEntry> resultList = new List<PricebookEntry>();
        for (Product2 p : bundles) {
            if (p.StockKeepingUnit == null || !p.StockKeepingUnit.endsWith(' - Bundle')) continue;

            String baseSKU = p.StockKeepingUnit.replace(' - Bundle', '');
            Id originalId = skuToProd.get(baseSKU);
            Decimal price = prodToPrice.get(originalId);

            if (originalId == null || price == null) {
                errorMessages.add('Missing base SKU or price for bundle: ' + p.StockKeepingUnit);
                continue;
            }

            String key = p.Id + '-' + pbId + '-' + psmoId + '-' + price;
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
            resultList.add(pbe);
        }
        return resultList;
    }

    private void performDML(List<SObject> dmlList, String context, String option) {
        if (dmlList.isEmpty()) return;
        try {
            if (option == 'insert') {
                Database.SaveResult[] insertResults = Database.insert(dmlList, false);
                processResults(insertResults, context);
            } else if (option == 'upsert') {
                Database.UpsertResult[] upsertResults = Database.upsert(dmlList, false);
                processResults(upsertResults, context);
            } else if (option == 'update') {
                Database.SaveResult[] updateResults = Database.update(dmlList, false);
                processResults(updateResults, context);
            } else {
                errorMessages.add(context + ' failed: Unsupported DML operation "' + option + '"');
                return;
            }
        } catch (Exception e) {
            errorMessages.add('Exception in ' + context + ': ' + e.getMessage());
        }
    }
    
    // Helper method to handle both SaveResult and UpsertResult
    private void processResults(Database.SaveResult[] results, String context) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
    }
    
    // Overloaded method for UpsertResult
    private void processResults(Database.UpsertResult[] results, String context) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                errorMessages.add(context + ' failed at index ' + i + ': ' + results[i].getErrors()[0].getMessage());
            }
        }
    }

    private void sendErrorEmail() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA_PricebookBatchVersion2 Errors');
        mail.setPlainTextBody('The batch encountered errors:\n\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}