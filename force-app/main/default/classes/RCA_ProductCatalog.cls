global class RCA_ProductCatalog implements Database.Batchable<SObject>, Database.Stateful {

    // List to store error messages encountered during batch execution
    private List<String> errorMessages = new List<String>();
    
    // Stores default category ID used for category assignment
    private Id defaultCategoryId;
    
    // Stores relationship type ID used for related component mapping
    private Id relationshipTypeId;

    // List of product IDs to process selectively, if provided
    private List<Id> productIds;

    // Default constructor
    global RCA_ProductCatalog() {}

    // Constructor to initialize batch with specific product IDs
    global RCA_ProductCatalog(List<Id> productIds) {
        this.productIds = productIds;
    }

    // Start method to build the query for fetching unprocessed Product2 records with related options and features
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

        // Apply filter if specific product IDs are provided
        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' AND Id IN :productIds';
        }
        return Database.getQueryLocator(baseQuery);
    }

    // Main execution logic
    global void execute(Database.BatchableContext bc, List<Product2> CPQProductsList) {
        // Initialize required configuration IDs
        initializeConfigIds();

        // Fetch related features and options for all input products
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogHelper.fetchFeatures(CPQProductsList);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogHelper.fetchOptions(CPQProductsList);

        // Lists to hold DML records
        List<Product2> allNewProducts = new List<Product2>();
        List<Product2> allUpdatedProducts = new List<Product2>();
        List<ProductComponentGroup> allComponentGroups = new List<ProductComponentGroup>();
        List<ProductRelatedComponent> allRelatedComponents = new List<ProductRelatedComponent>();
        List<Product2> toMarkProcessed = new List<Product2>();

        // Maps to track relationships between original and newly created products
        Map<Id, List<Product2>> cpqToNewProductsMap = new Map<Id, List<Product2>>();
        Map<Id, Map<Id, Product2>> cpqToOrigCPQToNewBundleMap = new Map<Id, Map<Id, Product2>>();

        // Process each CPQ product
        for (Product2 cpqProduct : CPQProductsList) {
            try {
                List<Product2> newProducts = new List<Product2>();
                List<Product2> updatedProducts = new List<Product2>();
                Map<Id, Product2> origCPQToNewBundle = new Map<Id, Product2>();

                // Build new and updated products
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

        // Perform insert and update DML operations
        handleDmlOperation(allNewProducts, 'insert', 'Insert Product failed');
        handleDmlOperation(allUpdatedProducts, 'update', 'Update Product failed');

        // Fetch IDs of inserted products to resolve relationships
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

        // Reset component collections
        allComponentGroups.clear();
        allRelatedComponents.clear();

        // Build component groups and related components using resolved products
        for (Id cpqId : cpqToNewProductsMap.keySet()) {
            Map<Id, Product2> origCPQToNewBundle = cpqToOrigCPQToNewBundleMap.get(cpqId);
            List<Product2> newProducts = cpqToNewProductsMap.get(cpqId);

            List<Product2> resolvedNewProducts = new List<Product2>();
            Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();
            for (Id origId : origCPQToNewBundle.keySet()) {
                Product2 tempProd = origCPQToNewBundle.get(origId);
                Product2 insertedProd = insertedProductMap.get(tempProd.StockKeepingUnit);
                resolvedOrigCPQToNewBundle.put(origId, insertedProd != null ? insertedProd : tempProd);
            }
            for (Product2 np : newProducts) {
                Product2 insertedProd = insertedProductMap.get(np.StockKeepingUnit);
                resolvedNewProducts.add(insertedProd != null ? insertedProd : np);
            }

            List<ProductComponentGroup> groups = RCA_ProductCatalogHelper.buildComponentGroups(resolvedOrigCPQToNewBundle, featureMap);
            allComponentGroups.addAll(groups);

            List<ProductRelatedComponent> relatedComponents =
                RCA_ProductCatalogHelper.buildRelatedComponents(resolvedOrigCPQToNewBundle, optionMap, groups, relationshipTypeId);
            allRelatedComponents.addAll(relatedComponents);
        }

        // Insert component groups and related components
        handleDmlOperation(allComponentGroups, 'insert', 'Component Group insert failed');
        handleDmlOperation(allRelatedComponents, 'insert', 'Related Component insert failed');

        // Build and insert category-product links
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
        handleDmlOperation(allCategoryLinks, 'insert', 'Category Assignment failed');

        // Mark original CPQ products as processed
        markProductsProcessed(toMarkProcessed);
    }

    // Final method to send error report if any issues occurred
    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    // Helper to initialize configuration IDs
    private void initializeConfigIds() {
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();
    }

    // Marks products as processed after execution
    private void markProductsProcessed(List<Product2> processedProducts) {
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
        }
        handleDmlOperation(processedProducts, 'update', 'Mark processed failed');
    }

    // Sends email notification with all captured errors
    private void sendErrorNotification() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA Product Catalog Batch Process Errors');
        mail.setPlainTextBody('Errors during batch execution:\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // Generic DML handler with error tracking
    private void handleDmlOperation(List<SObject> records, String operation, String errorContext) {
        if (records.isEmpty()) return;

        try {
            Database.SaveResult[] results;
            if (operation == 'insert') {
                results = Database.insert(records, false);
            } else if (operation == 'update') {
                results = Database.update(records, false);
            } else {
                throw new IllegalArgumentException('Unsupported DML operation: ' + operation);
            }

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