global class RCA_ProductCatalog implements Database.Batchable<SObject>, Database.Stateful {

    private List<String> errorMessages = new List<String>();
    private Id defaultCategoryId;
    private Id relationshipTypeId;
    private List<Id> productIds;

    global RCA_ProductCatalog() {}

    global RCA_ProductCatalog(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery =
            'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, ' +
            'SBQQ__Component__c, StockKeepingUnit, RecordTypeId, ' +
            '(SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, ' +
            'SBQQ__Required__c, SBQQ__Quantity__c, SBQQ__Feature__c, SBQQ__Feature__r.Name, ' +
            'SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, ' +
            'SBQQ__Bundled__c FROM SBQQ__Options__r), ' +
            '(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, ' +
            'SBQQ__Number__c FROM SBQQ__Features__r) ' +
            'FROM Product2 WHERE IsProcessed__c = FALSE';
        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' AND Id IN :productIds';
        }
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext bc, List<Product2> CPQProductsList) {
        initializeConfigIds();

        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogHelper.fetchFeatures(CPQProductsList);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogHelper.fetchOptions(CPQProductsList);

        List<Product2> allNewProducts = new List<Product2>();
        List<Product2> allUpdatedProducts = new List<Product2>();
        List<ProductComponentGroup> allComponentGroups = new List<ProductComponentGroup>();
        List<ProductRelatedComponent> allRelatedComponents = new List<ProductRelatedComponent>();
        List<Product2> toMarkProcessed = new List<Product2>();

        Map<Id, List<Product2>> cpqToNewProductsMap = new Map<Id, List<Product2>>();
        Map<Id, Map<Id, Product2>> cpqToOrigCPQToNewBundleMap = new Map<Id, Map<Id, Product2>>();

        for (Product2 cpqProduct : CPQProductsList) {
            try {
                List<Product2> newProducts = new List<Product2>();
                List<Product2> updatedProducts = new List<Product2>();
                Map<Id, Product2> origCPQToNewBundle = new Map<Id, Product2>();

                RCA_ProductCatalogHelper.buildProducts(
                    new List<Product2>{cpqProduct}, featureMap, optionMap,
                    newProducts, updatedProducts, origCPQToNewBundle
                );

                if (newProducts.isEmpty()) continue;

                allNewProducts.addAll(newProducts);
                allUpdatedProducts.addAll(updatedProducts);
                cpqToNewProductsMap.put(cpqProduct.Id, newProducts);
                cpqToOrigCPQToNewBundleMap.put(cpqProduct.Id, origCPQToNewBundle);

                toMarkProcessed.add(cpqProduct);
            } catch (Exception ex) {
                errorMessages.add('Unexpected error for Product SKU ' + cpqProduct.StockKeepingUnit + ': ' + ex.getMessage());
            }
        }

        handleDml(allNewProducts, 'Insert Product failed');
        handleDmlUpdate(allUpdatedProducts, 'Update Product failed');

        Map<String, Product2> insertedProductMap = new Map<String, Product2>();
        if (!allNewProducts.isEmpty()) {
            Set<String> skus = new Set<String>();
            for (Product2 p : allNewProducts) {
                if (p.StockKeepingUnit != null) skus.add(p.StockKeepingUnit);
            }
            for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :skus]) {
                insertedProductMap.put(p.StockKeepingUnit, p);
            }
        }

        // PROCESS EACH CPQ PRODUCT: build & insert groups first, then related components
        for (Id cpqId : cpqToNewProductsMap.keySet()) {
            Map<Id, Product2> origCPQToNewBundle = cpqToOrigCPQToNewBundleMap.get(cpqId);
            List<Product2> newProducts = cpqToNewProductsMap.get(cpqId);

            List<Product2> resolvedNewProducts = new List<Product2>();
            Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();
            for (Id origId : origCPQToNewBundle.keySet()) {
                Product2 tempProd = origCPQToNewBundle.get(origId);
                Product2 insertedProd = insertedProductMap.get(tempProd.StockKeepingUnit);
                if (insertedProd != null) {
                    resolvedOrigCPQToNewBundle.put(origId, insertedProd);
                } else {
                    resolvedOrigCPQToNewBundle.put(origId, tempProd);
                }
            }
            for (Product2 np : newProducts) {
                Product2 insertedProd = insertedProductMap.get(np.StockKeepingUnit);
                if (insertedProd != null) {
                    resolvedNewProducts.add(insertedProd);
                } else {
                    resolvedNewProducts.add(np);
                }
            }

            // Build component groups
            List<ProductComponentGroup> groups = RCA_ProductCatalogHelper.buildComponentGroups(resolvedOrigCPQToNewBundle, featureMap);

            // Insert groups immediately to get their Ids
            if (!groups.isEmpty()) {
                try {
                    insert groups;
                    allComponentGroups.addAll(groups);
                } catch (Exception e) {
                    errorMessages.add('Component Group insert failed for CPQ Product Id ' + cpqId + ': ' + e.getMessage());
                    continue; // Skip related components for this product if groups insert fails
                }
            }

            // Build related components using inserted groups (with valid Ids)
            List<ProductRelatedComponent> relatedComponents =
                RCA_ProductCatalogHelper.buildRelatedComponents(resolvedOrigCPQToNewBundle, optionMap, groups, relationshipTypeId);

            if (!relatedComponents.isEmpty()) {
                try {
                    insert relatedComponents;
                    allRelatedComponents.addAll(relatedComponents);
                } catch (Exception e) {
                    errorMessages.add('Related Component insert failed for CPQ Product Id ' + cpqId + ': ' + e.getMessage());
                }
            }
        }

        // Assign categories after components created
        List<ProductCategoryProduct> allCategoryLinks = new List<ProductCategoryProduct>();
        for (Product2 cpqProduct : CPQProductsList) {
            List<Product2> newProducts = cpqToNewProductsMap.get(cpqProduct.Id);
            if (newProducts == null) continue;

            List<Product2> resolvedProducts = new List<Product2>();
            for (Product2 p : newProducts) {
                if (insertedProductMap.containsKey(p.StockKeepingUnit)) {
                    resolvedProducts.add(insertedProductMap.get(p.StockKeepingUnit));
                }
            }

            List<ProductCategoryProduct> categoryList = new List<ProductCategoryProduct>();
            RCA_ProductCatalogHelper.assignCategory(
                new List<Product2>{cpqProduct},
                resolvedProducts,
                categoryList,
                defaultCategoryId
            );

            allCategoryLinks.addAll(categoryList);
        }
        handleDml(allCategoryLinks, 'Category Assignment failed');

        // Mark processed products
        markProductsProcessed(toMarkProcessed);
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    private void initializeConfigIds() {
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();
    }

    private void markProductsProcessed(List<Product2> processedProducts) {
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
        }
        handleDmlUpdate(processedProducts, 'Mark processed failed');
    }

    private void sendErrorNotification() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA Product Catalog Batch Process Errors');
        mail.setPlainTextBody('Errors during batch execution:\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    private void handleDml(List<SObject> records, String errorContext) {
        if (records.isEmpty()) return;
        try {
            Database.SaveResult[] results = Database.insert(records, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    errorMessages.add(RCA_BatchExceptionLogger.logException(
                        'RCA_ProductCatalog', errorContext,
                        records[i].get('Id'), results[i].getErrors()[0]
                    ));
                }
            }
        } catch (Exception e) {
            errorMessages.add(errorContext + ' - Unexpected DML error: ' + e.getMessage());
        }
    }

    private void handleDmlUpdate(List<SObject> records, String errorContext) {
        if (records.isEmpty()) return;
        try {
            Database.SaveResult[] results = Database.update(records, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    errorMessages.add(RCA_BatchExceptionLogger.logException(
                        'RCA_ProductCatalog', errorContext,
                        records[i].get('Id'), results[i].getErrors()[0]
                    ));
                }
            }
        } catch (Exception e) {
            errorMessages.add(errorContext + ' - Unexpected DML error: ' + e.getMessage());
        }
    }
}
