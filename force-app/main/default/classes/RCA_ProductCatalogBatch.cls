// Refactored RCA_ProductCatalogBatch class with RCA_BatchExceptionLogger integration

global class RCA_ProductCatalogBatch implements Database.Batchable<SObject>, Database.Stateful {

    public Id defaultCategoryId;
    public Id relationshipTypeId;
    private List<Id> productIds;
    public List<SObject> failedRecords = new List<SObject>();

    global RCA_ProductCatalogBatch() {}

    global RCA_ProductCatalogBatch(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String query = 'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, RecordTypeId, SBQQ__SubscriptionPercent__c, SBQQ__SubscriptionTarget__c, SBQQ__SubscriptionBase__c, SBQQ__PricingMethod__c, SBQQ__SubscriptionType__c, SBQQ__SubscriptionTerm__c, SBQQ__SubscriptionPricing__c, '
                     + '(SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c, '
                     + 'SBQQ__Feature__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__Bundled__c FROM SBQQ__Options__r), '
                     + '(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) '
                     + 'FROM Product2 WHERE IsProcessed__c = FALSE';

        if (productIds != null && !productIds.isEmpty()) {
            query += ' AND Id IN :productIds';
        }

        return Database.getQueryLocator(query);
    }

    global void execute(Database.BatchableContext bc, List<Product2> cpqProducts) {

        List<Product2> allNewProducts = new List<Product2>();
        List<Product2> allUpdatedProducts = new List<Product2>();
        List<ProductComponentGroup> allGroups = new List<ProductComponentGroup>();
        List<ProductRelatedComponent> allComponents = new List<ProductRelatedComponent>();
        Map<Id, Product2> allOrigCPQToNewBundleMap = new Map<Id, Product2>();

        Map<String, Id> config = RCA_ProductCatalogBatchHelper.initializeConfigIds();
        defaultCategoryId = config.get('defaultCategoryId');
        relationshipTypeId = config.get('relationshipTypeId');

        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogBatchHelper.fetchFeatures(cpqProducts);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogBatchHelper.fetchOptions(cpqProducts);

        try {
            RCA_ProductCatalogBatchHelper.buildProducts(cpqProducts, featureMap, optionMap, allNewProducts, allUpdatedProducts, allOrigCPQToNewBundleMap);
        } catch (Exception ex) {
            RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'buildProducts', 'Product2', null, ex.getMessage());
            RCA_BatchExceptionLogger.flushLogs();
            return;
        }

        RCA_ProductCatalogBatchHelper.handleDmlOperation(allNewProducts, 'insert', 'Inserting Product2 failed', failedRecords);
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allUpdatedProducts, 'update', 'Updating Product2 failed', failedRecords);

        Map<String, Product2> insertedProductMap = new Map<String, Product2>();
        try {
            RCA_ProductCatalogBatchHelper.buildNewProductsMap(allNewProducts, insertedProductMap);
        } catch (Exception ex) {
            RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'buildNewProductsMap', 'Product2', null, ex.getMessage());
            RCA_BatchExceptionLogger.flushLogs();
            return;
        }

        Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();
        try {
            List<ProductComponentGroup> groups = RCA_ProductCatalogBatchHelper.buildComponentGroups(resolvedOrigCPQToNewBundle, featureMap, allOrigCPQToNewBundleMap, insertedProductMap, optionMap);
            allGroups.addAll(groups);
        } catch (Exception ex) {
            RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'buildComponentGroups', 'ProductComponentGroup', null, ex.getMessage());
            RCA_BatchExceptionLogger.flushLogs();
            return;
        }

        RCA_ProductCatalogBatchHelper.handleDmlOperation(allGroups, 'insert', 'Inserting ProductComponentGroup failed', failedRecords);

        Map<Id, Product2> resolvedOrigCPQOptionsToNewBundle = new Map<Id, Product2>();
        try {
            List<ProductRelatedComponent> components = RCA_ProductCatalogBatchHelper.buildRelatedComponents(resolvedOrigCPQOptionsToNewBundle, optionMap, allGroups, relationshipTypeId, allOrigCPQToNewBundleMap, insertedProductMap);
            allComponents.addAll(components);
        } catch (Exception ex) {
            RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'buildRelatedComponents', 'ProductRelatedComponent', null, ex.getMessage());
            RCA_BatchExceptionLogger.flushLogs();
            return;
        }

        RCA_ProductCatalogBatchHelper.handleDmlOperation(allComponents, 'insert', 'Inserting ProductRelatedComponent failed', failedRecords);

        List<ProductCategoryProduct> allCategoryLinks = new List<ProductCategoryProduct>();
        try {
            List<ProductCategoryProduct> links = RCA_ProductCatalogBatchHelper.assignCategory(defaultCategoryId, cpqProducts, allOrigCPQToNewBundleMap, insertedProductMap);
            allCategoryLinks.addAll(links);
        } catch (Exception ex) {
            RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'assignCategory', 'ProductCategoryProduct', null, ex.getMessage());
            RCA_BatchExceptionLogger.flushLogs();
            return;
        }

        RCA_ProductCatalogBatchHelper.handleDmlOperation(allCategoryLinks, 'insert', 'Category Assignment failed', failedRecords);
        RCA_ProductCatalogBatchHelper.markProductsProcessed(cpqProducts, failedRecords);

        if (!failedRecords.isEmpty()) {
            try {
                RCA_ProductCatalogBatchHelper.rollbackFailedCPQHierarchy(failedRecords);
            } catch (Exception ex) {
                RCA_BatchExceptionLogger.logExceptions('RCA_ProductCatalogBatch', 'rollbackFailedCPQHierarchy', 'Product2', null, ex.getMessage());
                RCA_BatchExceptionLogger.flushLogs();
            }
        }
        
    }

    global void finish(Database.BatchableContext bc) {
        RCA_BatchExceptionLogger.flushLogs();
    }
}