global class RCA_PricebookBatchVersion2 implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();

    global RCA_PricebookBatchVersion2(List<Id> productIds) {
        this.productIds = productIds;
    }

    global RCA_PricebookBatchVersion2() {}

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type FROM Product2';
        if (productIds != null && !productIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' WHERE Id IN :productIds');
        }
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext bc, List<Product2> allProductsList) {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        if (config == null) {
            errorMessages.add('Missing Pricing_Method_Config__mdt configuration.');
            return;
        }

        String type = config.ProductType__c;
        String standardPricebookId = config.Standard_Price_book__c;
        String rcaPricebookId = config.RCA_PricebookId__c;
        String psmoId = config.One_Time_Selling_Model__c;

        if (String.isBlank(standardPricebookId) || String.isBlank(rcaPricebookId) || String.isBlank(psmoId)) {
            errorMessages.add('Configuration values are missing in metadata.');
            return;
        }

        List<Product2> newBundleProductsList = new List<Product2>();
        List<Product2> oldProductsBeforeMigration = new List<Product2>();
        for (Product2 product : allProductsList) {
            if (product.Type == type) {
                newBundleProductsList.add(product);
            } else {
                oldProductsBeforeMigration.add(product);
            }
        }

        Map<Id, Id> oldProductToPSMO = new Map<Id, Id>();
        if (!oldProductsBeforeMigration.isEmpty()) {
            List<Id> oldProductIds = new List<Id>();
            for (Product2 product : oldProductsBeforeMigration) {
                oldProductIds.add(product.Id);
            }

            Map<Id, ProductSellingModelOption> existingPSMOsMap = new Map<Id, ProductSellingModelOption>();
            for (ProductSellingModelOption psmo : [
                SELECT Id, Product2Id, ProductSellingModelId
                FROM ProductSellingModelOption
                WHERE Product2Id IN :oldProductIds AND ProductSellingModelId = :psmoId
            ]) {
                existingPSMOsMap.put(psmo.Product2Id, psmo);
            }

            List<ProductSellingModelOption> oldPSMOs = new List<ProductSellingModelOption>();
            for (Product2 product : oldProductsBeforeMigration) {
                ProductSellingModelOption toUpsert = new ProductSellingModelOption(
                    Product2Id = product.Id,
                    ProductSellingModelId = psmoId
                );
                if (existingPSMOsMap.containsKey(product.Id)) {
                    toUpsert.Id = existingPSMOsMap.get(product.Id).Id;
                }
                oldPSMOs.add(toUpsert);
                oldProductToPSMO.put(product.Id, psmoId);
            }

            performDML(oldPSMOs, 'Upsert: Old PSMOs', 'upsert');
        }


        List<PricebookEntry> oldStdEntries = [
            SELECT Id, Pricebook2Id, Product2Id, UnitPrice, ProductSellingModelId, IsActive
            FROM PricebookEntry
            WHERE Product2Id IN :oldProductsBeforeMigration
            AND Pricebook2Id = :standardPricebookId
        ];

        //Get all existing PBE's for Standard and RCA PirceBooks - 
        Map<String, Id> existingKeyToIdMap = new Map<String, Id>();
        for (PricebookEntry existing : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :oldProductsBeforeMigration AND Pricebook2Id IN :new List<Id>{standardPricebookId, rcaPricebookId}]) {

            String key = existing.Product2Id + '-' + existing.Pricebook2Id + '-' + existing.ProductSellingModelId + '-' + existing.UnitPrice;
            existingKeyToIdMap.put(key, existing.Id);
        }

        System.debug('existingKeyToIdMap-->>> ' + existingKeyToIdMap.keySet());

        // First create a standard PBE if not present - 
        List<PricebookEntry> cloneStd = new List<PricebookEntry>();
        for (PricebookEntry entry : oldStdEntries) {

            String key = entry.Product2Id + '-' + entry.Pricebook2Id + '-' + entry.ProductSellingModelId;

            PricebookEntry newStdPBE = new PricebookEntry();
            newStdPBE.Product2Id = entry.Product2Id;
            newStdPBE.Pricebook2Id = entry.Pricebook2Id;
            newStdPBE.ProductSellingModelId = sellingModelId;
            newStdPBE.UnitPrice = entry.UnitPrice;
            newStdPBE.IsActive = entry.IsActive;

            if (existingKeyToIdMap.containsKey(key)) {
                newStdPBE.Id = existingKeyToIdMap.get(key); 
            }
            cloneStd.add(newStdPBE);
        }

        performDML(cloneStd, 'Upsert: Standard Pricebook Clones', 'upsert');
        
        // Then create a similar PBE for the above inserted list with RCA_PriceBook - 
        List<PricebookEntry> cloneRca = new List<PricebookEntry>();
        for (PricebookEntry entry : cloneStd) {
            String key = entry.Product2Id + '-' + rcaPricebookId + '-' + entry.ProductSellingModelId + '-' + entry.UnitPrice;

            PricebookEntry rcaPBE = new PricebookEntry();
            rcaPBE.Product2Id = entry.Product2Id;
            rcaPBE.Pricebook2Id = rcaPricebookId;
            rcaPBE.ProductSellingModelId = entry.ProductSellingModelId;
            rcaPBE.UnitPrice = entry.UnitPrice;
            rcaPBE.IsActive = entry.IsActive;

            if (existingKeyToIdMap.containsKey(key)) {
                rcaPBE.Id = existingKeyToIdMap.get(key); 
            }

            cloneRca.add(rcaPBE);
        }

        performDML(cloneRca, 'Upsert: RCA Pricebook Clones', 'upsert');

        
        //Map of Old CPQ Products and their SKU's - 
        Map<String, Id> skuToProductIdMap = new Map<String, Id>();
        for (Product2 p : oldProductsBeforeMigration) {
            if (String.isNotBlank(p.StockKeepingUnit)) {
                skuToProductIdMap.put(p.StockKeepingUnit, p.Id);
            }
        }

        //Map of Old CPQ Products and their prices - 
        Map<Id, Decimal> productIdToPriceMap = new Map<Id, Decimal>();
        for (PricebookEntry entry : oldStdEntries) {
            productIdToPriceMap.put(entry.Product2Id, entry.UnitPrice);
        }

        //Create PSMO's for new bundle products --
        List<ProductSellingModelOption> newBundlePSMOs = new List<ProductSellingModelOption>();
        Map<Id, ProductSellingModelOption> existingnewPSMOsMap = new Map<Id, ProductSellingModelOption>();
            for (ProductSellingModelOption psmo : [
                SELECT Id, Product2Id, ProductSellingModelId FROM ProductSellingModelOption
                WHERE Product2Id IN :newBundleProductsList AND ProductSellingModelId = :psmoId
            ]) {
                existingnewPSMOsMap.put(psmo.Product2Id, psmo);
            }

            List<ProductSellingModelOption> newBundlePSMOs = new List<ProductSellingModelOption>();
            for (Product2 product : newBundleProductsList) {
                ProductSellingModelOption toNewUpsert = new ProductSellingModelOption(
                    Product2Id = product.Id,
                    ProductSellingModelId = psmoId
                );
                if (existingnewPSMOsMap.containsKey(product.Id)) {
                    toNewUpsert.Id = existingnewPSMOsMap.get(product.Id).Id;
                }
                newBundlePSMOs.add(toUpsert);
            }

            performDML(newBundlePSMOs, 'Upsert: New PSMOs', 'upsert');
        
        

        //Get all existing PBE's for new Products for Standard and RCA PirceBooks - 
        Map<String, Id> existingNewKeyToIdMap = new Map<String, Id>();
        for (PricebookEntry existing : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice
            FROM PricebookEntry
            WHERE Product2Id IN :newBundleProductsList AND Pricebook2Id IN :new List<Id>{standardPricebookId, rcaPricebookId}]) {

            String key = existing.Product2Id + '-' + existing.Pricebook2Id + '-' + existing.ProductSellingModelId + '-' + existing.UnitPrice;
            existingNewKeyToIdMap.put(key, existing.Id);
        }

        System.debug('existingNewKeyToIdMap-->>> ' + existingNewKeyToIdMap.keySet());


        // First create a standard PBE if not present - 
        for (PricebookEntry bundle : newBundleProductsList) {

            if (bundle.StockKeepingUnit == null) continue;

            String derivedSKU = bundle.StockKeepingUnit.replace(' - Bundle', '');
            Id originalProductId = skuToProductIdMap.get(derivedSKU);
            Decimal price = productIdToPriceMap.get(originalProductId);

            String key = bundle.Product2Id + '-' + bundle.Pricebook2Id + '-' + bundle.ProductSellingModelIdingModelId + '-' + bundle.UnitPrice;

            PricebookEntry newBundleStdPBE = new PricebookEntry();
            newStdPBE.Product2Id = bundle.Product2Id;
            newStdPBE.Pricebook2Id = bundle.Pricebook2Id;
            newStdPBE.ProductSellingModelId = bundle.ProductSellingModelIdingModelId;
            newStdPBE.UnitPrice = price;
            newStdPBE.IsActive = bundle.IsActive;

            if (existingNewKeyToIdMap.containsKey(key)) {
                newStdPBE.Id = existingNewKeyToIdMap.get(key); 
            }
            newBundleStdPBEs.add(newStdPBE);
        }

        performDML(newBundleStdPBEs, 'Upsert: Standard Pricebook Clones', 'upsert');

        //Create RCA PBE for the new products from RCA PriceBooks - 
        List<PricebookEntry> newBundleRCAPBEs = new List<PricebookEntry>();
        for (PricebookEntry entry : newBundleStdPBEs) {

            String key = bundle.Product2Id + '-' + bundle.Pricebook2Id + '-' + bundle.ProductSellingModelIdingModelId + '-' + bundle.UnitPrice;

            PricebookEntry newRCABundleStdPBE = new PricebookEntry();
            newStdPBE.Product2Id = bundle.Product2Id;
            newStdPBE.Pricebook2Id = bundle.Pricebook2Id;
            newStdPBE.ProductSellingModelId = bundle.ProductSellingModelIdingModelId;
            newStdPBE.UnitPrice = bundle.UnitPrice;
            newStdPBE.IsActive = bundle.IsActive;

            if (existingNewKeyToIdMap.containsKey(key)) {
                newRCABundleStdPBE.Id = existingNewKeyToIdMap.get(key); 
            }
            newBundleStdPBEs.add(newStdPBE);
        }
        performDML(newBundleRCAPBEs, 'upsert: New Bundle RCA PBEs', 'upsert');
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorEmail();
        } else {
            System.debug('RCA_PricebookBatch completed successfully with no errors.');
        }
    }

    private void performDML(List<SObject> dmlList, String context, String option) {
        if (!dmlList.isEmpty()) {
            try {
                Database.SaveResult[] results;
                if (option == 'insert') {
                    results = Database.insert(dmlList, false);
                } else if (option == 'upsert') {
                    results = Database.upsert(dmlList, false);
                } else if (option == 'update') {
                    results = Database.update(dmlList, false);
                } else {
                    errorMessages.add(context + ' failed: Unsupported DML operation "' + option + '"');
                    return;
                }

                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        errorMessages.add(context + ' failed for record index ' + i + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            } catch (Exception e) {
                errorMessages.add('Exception during ' + context + ': ' + e.getMessage());
            }
        }
    }

    private void sendErrorEmail() {
        String adminEmail = 'Shubham.m@etg.digital';
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { adminEmail });
        mail.setSubject('RCA_PricebookBatchVersion2 Errors');
        mail.setPlainTextBody('The batch encountered the following errors:\n\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}
