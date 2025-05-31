global class RCA_ProductCatalogBatch implements Database.Batchable<SObject>, Database.Stateful {

    private List<String> errorMessages = new List<String>();
    public Id defaultCategoryId;
    public Id relationshipTypeId;
    private List<Id> productIds;
    public List<SObject> failedRecords = new List<SObject>();
    

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

        List<Product2> allNewProducts = new List<Product2>();
        List<Product2> allUpdatedProducts = new List<Product2>();
        List<ProductComponentGroup> allGroups = new List<ProductComponentGroup>();
        List<ProductRelatedComponent> allComponents = new List<ProductRelatedComponent>();
        Map<Id, Product2> allOrigCPQToNewBundleMap = new  Map<Id, Product2>();
        

        //(Prepare data) -> Initialize categories and ChildRelationshipTypeIds - 
        Map<String, Id> config = RCA_ProductCatalogBatchHelper.initializeConfigIds();
        defaultCategoryId = config.get('defaultCategoryId');
        relationshipTypeId = config.get('relationshipTypeId');


        // (Prepare data) -> Fetch CPQ Product Features and Product Options - 
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogBatchHelper.fetchFeatures(cpqProducts);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogBatchHelper.fetchOptions(cpqProducts);


        //1. (Prepare data) -> Build new bundle products and update existing CPQ products, along with bundle mapping
        try {
            RCA_ProductCatalogBatchHelper.buildProducts(cpqProducts, featureMap, optionMap, allNewProducts, allUpdatedProducts, allOrigCPQToNewBundleMap);
        } catch (Exception ex) {
            errorMessages.add('Error during buildProducts: ' + ex.getMessage());
            return;
        }

        //2.(DML) -> Insert new products and update existing ones - 
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allNewProducts, 'insert', 'Inserting Product2 failed', errorMessages, failedRecords);

        //3. (DML) -> Update existing ones - 
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allUpdatedProducts, 'update', 'Updating Product2 failed', errorMessages, failedRecords);

        //4.(Prepare data) -> Build map of newly inserted products by SKU for later reference
        Map<String, Product2> insertedProductMap = new Map<String, Product2>();
        try {
            RCA_ProductCatalogBatchHelper.buildNewProductsMap(allNewProducts, insertedProductMap);
        } catch (Exception ex) {
            errorMessages.add('Error during building New Products Map: ' + ex.getMessage());
            return;
        }

        //5. (Prepare data) -> Build ProductComponentGroup records for each CPQ product bundle
        Map<Id, Product2> resolvedOrigCPQToNewBundle = new Map<Id, Product2>();
        try {
            List<ProductComponentGroup> groups = RCA_ProductCatalogBatchHelper.buildComponentGroups(resolvedOrigCPQToNewBundle, featureMap, allOrigCPQToNewBundleMap, insertedProductMap);
            allGroups.addAll(groups);
        } catch (Exception ex) {
            errorMessages.add('Error during building New ProductComponentGroup: ' + ex.getMessage());
            return;
        }

        //6. (DML) -> Insert ProductComponentGroupgroups and collect their IDs
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allGroups, 'insert', 'Inserting ProductComponentGroup failed', errorMessages, failedRecords);

        //7.(Prepare data) -> Build related components using inserted product and group IDs
        Map<Id, Product2> resolvedOrigCPQOptionsToNewBundle = new Map<Id, Product2>();
        try {
            List<ProductRelatedComponent> components = RCA_ProductCatalogBatchHelper.buildRelatedComponents(resolvedOrigCPQOptionsToNewBundle, optionMap, allGroups, relationshipTypeId, allOrigCPQToNewBundleMap, insertedProductMap);
            allComponents.addAll(components);
        } catch (Exception ex) {
            errorMessages.add('Error during building New ProductRelatedComponent: ' + ex.getMessage());
            return;
        }
        
        //8. (DML) -> Insert all related components
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allComponents, 'insert', 'Inserting ProductRelatedComponent failed', errorMessages, failedRecords);

        //9. (Prepare data) -> Build category links for each CPQ product bundle
        List<ProductCategoryProduct> allCategoryLinks = new List<ProductCategoryProduct>();
        try {
            List<ProductCategoryProduct> links = RCA_ProductCatalogBatchHelper.assignCategory(
            defaultCategoryId, cpqProducts, allOrigCPQToNewBundleMap, insertedProductMap );
            allCategoryLinks.addAll(links);
        } catch (Exception ex) {
            errorMessages.add('Error during building New Category Links: ' + ex.getMessage());
            return;
        }

        //10. (DML) -> Insert category links
        RCA_ProductCatalogBatchHelper.handleDmlOperation(allCategoryLinks, 'insert', 'Category Assignment failed', errorMessages, failedRecords);
        

        //11.(DML) -> Finally mark source CPQ products as processed
        RCA_ProductCatalogBatchHelper.markProductsProcessed(cpqProducts, errorMessages, failedRecords);
    }

    // Send an error notification after the batch completes
    global void finish(Database.BatchableContext bc) {

        if (!errorMessages.isEmpty()) {
            System.debug('Failed records -->> ' + JSON.serializePretty(failedRecords));
    
            try {
                // Step 1: Fetch successfully processed products (optional for context)
                List<Product2> processedProducts = [
                    SELECT Id, Name, IsProcessed__c FROM Product2 WHERE IsProcessed__c = TRUE
                ];
                
                // Step 3: Send email notification
                RCA_ProductCatalogBatchHelper.sendErrorNotification(errorMessages);
    
                // Step 4: Perform rollback/deletion after notification
                RCA_ProductCatalogBatchHelper.rollbackFailedCPQHierarchy(failedRecords, errorMessages);
    
            } catch (Exception ex) {
                System.debug('Exception while handling finish logic: ' + ex.getMessage());
            }
        }
    }

}