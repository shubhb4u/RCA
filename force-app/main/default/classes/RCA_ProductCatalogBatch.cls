global class RCA_ProductCatalogBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Stores any error messages encountered during execution
    private List<String> errorMessages = new List<String>();
    private Id defaultCategoryId;
    private Id relationshipTypeId;
    private List<Id> productIds;

    // Default constructor
    global RCA_ProductCatalogBatch() {}

    // Parameterized Constructor to allow selective execution by product IDs
    global RCA_ProductCatalogBatch(List<Id> productIds) {
        this.productIds = productIds;
    }

    // Query products that need processing (optionally filtered by productIds)
    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, '
                     + '(SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c, '
                     + 'SBQQ__Feature__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r), '
                     + '(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) '
                     + 'FROM Product2 WHERE IsProcessed__c = FALSE';

        if (productIds != null && !productIds.isEmpty()) {
            query += ' AND Id IN :productIds';
        }

        return Database.getQueryLocator(query);
    }

    // Core logic for product transformation and creation of related data
    global void execute(Database.BatchableContext bc, List<Product2> cpqProducts) {
        initializeConfigIds();

        // Fetch CPQ Features and Options
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogBatchHelper.fetchFeatures(cpqProducts);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogBatchHelper.fetchOptions(cpqProducts);

        List<Product2> allNewProducts = new List<Product2>();
        List<Product2> allUpdatedProducts = new List<Product2>();
        Map<Id, Map<Id, Product2>> allOrigCPQToNewBundleMap = new Map<Id, Map<Id, Product2>>();

        // Build new product and update list, along with bundle mapping
        try {
            RCA_ProductCatalogBatchHelper.buildProducts(cpqProducts, featureMap, optionMap, allNewProducts, allUpdatedProducts, allOrigCPQToNewBundleMap);
        } catch (Exception ex) {
            errorMessages.add('Error during buildProducts: ' + ex.getMessage());
            return;
        }

        // Insert new products and update existing ones - 
        handleDmlOperation(allNewProducts, 'insert', 'Inserting Product2 failed');
        handleDmlOperation(allUpdatedProducts, 'update', 'Updating Product2 failed');

        // Build map of newly inserted products by SKU for later reference
        Set<String> skuSet = new Set<String>();
        for (Product2 p : allNewProducts) {
            if (p.StockKeepingUnit != null) {
                skuSet.add(p.StockKeepingUnit);
            }
        }

        Map<String, Product2> insertedProductMap = new Map<String, Product2>();
        for (Product2 p : [
            SELECT Id, StockKeepingUnit
            FROM Product2
            WHERE StockKeepingUnit IN :skuSet
        ]) {
            insertedProductMap.put(p.StockKeepingUnit, p);
        }

        List<ProductComponentGroup> allGroups = new List<ProductComponentGroup>();
        List<ProductRelatedComponent> allComponents = new List<ProductRelatedComponent>();

        // Build ProductComponentGroup records for each CPQ product bundle
        for (Id cpqId : allOrigCPQToNewBundleMap.keySet()) {
            Map<Id, Product2> origCPQToNewBundle = allOrigCPQToNewBundleMap.get(cpqId);
            Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();

            for (Id origId : origCPQToNewBundle.keySet()) {
                Product2 p = origCPQToNewBundle.get(origId);
                Product2 resolved = insertedProductMap.get(p.StockKeepingUnit);
                if (resolved != null) resolvedOrigCPQToNewBundle.put(origId, resolved);
            }

            // Group construction before insert (IDs not needed yet)
            List<ProductComponentGroup> groups = RCA_ProductCatalogBatchHelper.buildComponentGroups(resolvedOrigCPQToNewBundle, featureMap);
            allGroups.addAll(groups);
        }

        // Insert groups and collect their IDs
        handleDmlOperation(allGroups, 'insert', 'Inserting ProductComponentGroup failed');

        // Build related components using inserted product and group IDs
        for (Id cpqId : allOrigCPQToNewBundleMap.keySet()) {
            Map<Id, Product2> origCPQToNewBundle = allOrigCPQToNewBundleMap.get(cpqId);
            Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();

            for (Id origId : origCPQToNewBundle.keySet()) {
                Product2 p = origCPQToNewBundle.get(origId);
                Product2 resolved = insertedProductMap.get(p.StockKeepingUnit);
                if (resolved != null) resolvedOrigCPQToNewBundle.put(origId, resolved);
            }

            // Build components related to products and groups
            List<ProductRelatedComponent> components = RCA_ProductCatalogBatchHelper.buildRelatedComponents(
                resolvedOrigCPQToNewBundle, optionMap, allGroups, relationshipTypeId);
            allComponents.addAll(components);
        }

        // Insert all related components
        handleDmlOperation(allComponents, 'insert', 'Inserting ProductRelatedComponent failed');

        // Category assignment logic
        List<ProductCategoryProduct> allCategoryLinks = new List<ProductCategoryProduct>();

        for (Product2 cpq : cpqProducts) {
            Map<Id, Product2> mappedBundles = allOrigCPQToNewBundleMap.get(cpq.Id);
            if (mappedBundles == null) continue;

            List<Product2> resolvedProducts = new List<Product2>();
            for (Product2 p : mappedBundles.values()) {
                Product2 resolved = insertedProductMap.get(p.StockKeepingUnit);
                if (resolved != null) resolvedProducts.add(resolved);
            }

            List<ProductCategoryProduct> links = new List<ProductCategoryProduct>();
            RCA_ProductCatalogBatchHelper.assignCategory(new List<Product2>{cpq}, resolvedProducts, links, defaultCategoryId);
            allCategoryLinks.addAll(links);
        }

        // Insert category linkages
        handleDmlOperation(allCategoryLinks, 'insert', 'Category Assignment failed');

        // Finally mark source CPQ products as processed
        markProductsProcessed(cpqProducts);
    }

    // Send an error notification after the batch completes
    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    // Fetch default config values used in component relationships and categories
    private void initializeConfigIds() {
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogBatchHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogBatchHelper.getRelationshipTypeId();
    }

    // Update Product2.IsProcessed__c = true
    private void markProductsProcessed(List<Product2> processedProducts) {
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
        }
        handleDmlOperation(processedProducts, 'update', 'Mark processed failed');
    }

    // Email errors to system administrator
    private void sendErrorNotification() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA Product Catalog Batch Process Errors');
        mail.setPlainTextBody('Errors during batch execution:\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }

    // Generic method to handle insert/update DMLs with error logging
    private void handleDmlOperation(List<SObject> records, String operation, String errorContext) {
        if (records.isEmpty()) return;
    
        try {
            System.debug('records getting inserted -->> ' + records);
            Database.SaveResult[] results = (operation == 'insert') ? Database.insert(records, false) : Database.update(records, false);
    
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    SObject record = records[i];
                    String errorRecordId = record.get('Id') != null
                        ? String.valueOf(record.get('Id'))
                        : record.get('ParentProductId') != null
                            ? String.valueOf(record.get('ParentProductId'))
                            : record.get('ProductId') != null
                                ? String.valueOf(record.get('ProductId'))
                                : 'UNKNOWN';
    
                    String objectType = record.getSObjectType().getDescribe().getName();
    
                    String fullErrorContext = errorContext + ' | Object: ' + objectType ;
    
                    errorMessages.add(RCA_BatchExceptionLogger.logException(
                        'RCA_ProductCatalogBatch', fullErrorContext,
                        errorRecordId, results[i].getErrors()[0]
                    ));
                }
            }
        } catch (Exception e) {
            errorMessages.add(errorContext + ' - Unexpected DML error: ' + e.getMessage());
        }
    }
}
