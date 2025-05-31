public class RCA_ProductCatalogBatchHelper {

    private static final String DEFAULT_CATEGORY_NAME = 'Default category';
    private static final String REL_TYPE              = 'Bundle';
    private static final String REL_TYPE_NAME         = 'BundleComponent';
    private static final String COMMON_GROUP_NAME     = 'Others';
    private static final Integer DEFAULT_MAX_COMPONENTS = 0;

    // Fetch default config values used in component relationships and categories
    public static Map<String, Id> initializeConfigIds() {

        //Map of default Categories - 
        Map<String, Id> config = new Map<String, Id>();
        config.put('defaultCategoryId', [SELECT Id FROM ProductCategory WHERE Name = :DEFAULT_CATEGORY_NAME LIMIT 1].Id);

        //Map of default RelationshipType Id -
        config.put('relationshipTypeId', [SELECT Id FROM ProductRelationshipType WHERE AssociatedProductRoleCat = :REL_TYPE_NAME AND MainProductRoleCat = :REL_TYPE LIMIT 1].Id);

        return config;
    }
    

    // Fetch features from related child records (expecting loaded relationship)
    public static Map<Id, List<SBQQ__ProductFeature__c>> fetchFeatures(List<Product2> CPQproducts) {
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        for (Product2 p : CPQproducts) {
            featureMap.put(p.Id, p.SBQQ__Features__r != null
                ? new List<SBQQ__ProductFeature__c>(p.SBQQ__Features__r)
                : new List<SBQQ__ProductFeature__c>());
        }
        return featureMap;
    }

    // 2. Fetch options from related child records (expecting loaded relationship)
    public static Map<Id, List<SBQQ__ProductOption__c>> fetchOptions(List<Product2> CPQproducts) {
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = new Map<Id, List<SBQQ__ProductOption__c>>();
        for (Product2 p : CPQproducts) {
            optionMap.put(p.Id, p.SBQQ__Options__r != null
                ? new List<SBQQ__ProductOption__c>(p.SBQQ__Options__r)
                : new List<SBQQ__ProductOption__c>());
        }
        return optionMap;
    }

    /**
     * 3. Build new bundle products and update existing CPQ products.
     * To return Map<Id, Map<Id, Product2>> to fit batch signature:
     * - Outer Map key = CPQ Product Id
     * - Inner Map key = CPQ Product Id (same) mapping to new Bundle product
     */
    public static void buildProducts(
        List<Product2> CPQProductsList,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<Product2> newProducts,
        List<Product2> updatedProducts,
        Map<Id, Product2> origCPQToNewBundleMap
    ) {
        for (Product2 product : CPQProductsList) {
            List<SBQQ__ProductFeature__c> features = featureMap.get(product.Id);
            List<SBQQ__ProductOption__c> options = optionMap.get(product.Id);

            Boolean hasFeatures = features != null && !features.isEmpty();
            Boolean hasOptions = options != null && !options.isEmpty();

            String baseName = String.isBlank(product.Name) ? 'PRD' : product.Name;
            String prefix = baseName.length() >= 3 ? baseName.substring(0, 3).toUpperCase() : baseName.toUpperCase();

            if (hasFeatures || hasOptions) {
                String skuBase = String.isBlank(product.StockKeepingUnit) ? prefix : product.StockKeepingUnit;

                Product2 bundle = new Product2(
                    Name = product.Name,
                    ProductCode = product.ProductCode + ' - Bundle',
                    IsActive = product.IsActive,
                    ConfigureDuringSale = product.SBQQ__ConfigurationType__c,
                    Type = 'Bundle',
                    StockKeepingUnit = skuBase + ' - Bundle'
                );

                newProducts.add(bundle);
                origCPQToNewBundleMap.put(product.Id, bundle);
            } else {
                // Update standalone CPQ products with relevant RCA fields
                product.ConfigureDuringSale = product.SBQQ__ConfigurationType__c;
                product.IsSoldOnlyWithOtherProds = product.SBQQ__Component__c;
                updatedProducts.add(product);
            }
        }
    }

    // Build map of newly inserted products by SKU for later reference
    public static void buildNewProductsMap(List<Product2> allNewProducts, Map<String, Product2> insertedProductMap){

        Set<String> skuSet = new Set<String>();
        for (Product2 p : allNewProducts) {
            if (p.StockKeepingUnit != null) {
                skuSet.add(p.StockKeepingUnit);
            }
        }
        
        for (Product2 p : [SELECT Id, StockKeepingUnit FROM Product2 WHERE 
                            StockKeepingUnit IN :skuSet]) {
            insertedProductMap.put(p.StockKeepingUnit, p);
        }
    }


    /**
     * 4. Assign default categories to new and updated products, avoiding duplicates
     */
    public static List<ProductCategoryProduct>  assignCategory(Id categoryId,
                List<Product2> updatedProducts,  
                Map<Id, Product2> allOrigCPQToNewBundleMap, 
                Map<String, Product2> insertedProductMap) {

        List<Product2> allProducts = new List<Product2>();
        allProducts.addAll(updatedProducts);

        for (Product2 cpq : updatedProducts) {
            Product2 bundle = allOrigCPQToNewBundleMap.get(cpq.Id);
            if (bundle != null) {
                Product2 resolved = insertedProductMap.get(bundle.StockKeepingUnit);
                allProducts.add(resolved);
            }
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : allProducts) {
            if (p.Id != null) productIds.add(p.Id);
        }

        Set<Id> existingProductIds = new Set<Id>();
        for (ProductCategoryProduct pcp : [SELECT ProductId FROM ProductCategoryProduct 
            WHERE ProductCategoryId = :categoryId 
            AND ProductId IN :productIds]) {
                existingProductIds.add(pcp.ProductId);
        }

        List<ProductCategoryProduct> links = new List< ProductCategoryProduct>();
        for (Product2 p : allProducts) {
            if (!existingProductIds.contains(p.Id)) {
                links.add(new ProductCategoryProduct(
                    ProductId = p.Id,
                    ProductCategoryId = categoryId
                ));
            }
        }
        return links;
    }

    /**
     * 5. Create ProductComponentGroups with default group + feature groups
     * Accepts resolved bundles map: Map<Id (origProductId), Product2 (new bundle)>
     */
    public static List<ProductComponentGroup> buildComponentGroups(
        Map<Id, Product2> resolvedOrigCPQToNewBundle,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, Product2> allOrigCPQToNewBundleMap,
        Map<String, Product2> insertedProductMap

    ) {
        List<ProductComponentGroup> groups = new List<ProductComponentGroup>();

        for (Id origId : allOrigCPQToNewBundleMap.keySet()) {
            Product2 p = allOrigCPQToNewBundleMap.get(origId);
            Product2 resolved = insertedProductMap.get(p.StockKeepingUnit);
            if (resolved != null) resolvedOrigCPQToNewBundle.put(origId, resolved);
        }

        for (Id origId : resolvedOrigCPQToNewBundle.keySet()) {
            Product2 newProd = resolvedOrigCPQToNewBundle.get(origId);

            // Default group 'Others'
            groups.add(new ProductComponentGroup(
                ParentProductId = newProd.Id,
                Name = COMMON_GROUP_NAME,
                MinBundleComponents = 0,
                MaxBundleComponents = DEFAULT_MAX_COMPONENTS,
                Sequence = 1
            ));

            List<SBQQ__ProductFeature__c> features = featureMap.get(origId);
            if (features != null) {
                for (SBQQ__ProductFeature__c feature : features) {
                    if (feature != null) {
                        groups.add(new ProductComponentGroup(
                            ParentProductId = newProd.Id,
                            Name = feature.Name,
                            MinBundleComponents = (feature.SBQQ__MinOptionCount__c != null) ? Integer.valueOf(feature.SBQQ__MinOptionCount__c) : 0,
                            MaxBundleComponents = (feature.SBQQ__MaxOptionCount__c != null)
                                ? Integer.valueOf(feature.SBQQ__MaxOptionCount__c)
                                : DEFAULT_MAX_COMPONENTS,
                            Sequence = (feature.SBQQ__Number__c != null) ? Integer.valueOf(feature.SBQQ__Number__c) : null
                        ));
                    }
                }
            }
        }
        return groups;
    }

    /**
     * 6. Build ProductRelatedComponents linking bundles, options & groups
     * Uses group Ids from created groups list, assumes groups are already inserted and have Ids
     */
    public static List<ProductRelatedComponent> buildRelatedComponents(
        Map<Id, Product2> resolvedOrigCPQOptionsToNewBundle,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<ProductComponentGroup> groups,
        Id relationshipTypeId,
        Map<Id, Product2> allOrigCPQToNewBundleMap,
        Map<String, Product2> insertedProductMap
    ) {


        List<ProductRelatedComponent> relatedComponents = new List<ProductRelatedComponent>();

        for (Id origId : allOrigCPQToNewBundleMap.keySet()) {
            Product2 p = allOrigCPQToNewBundleMap.get(origId);
            Product2 resolved = insertedProductMap.get(p.StockKeepingUnit);
            if (resolved != null) resolvedOrigCPQOptionsToNewBundle.put(origId, resolved);
        }

        Map<String, Id> groupLookup = new Map<String, Id>();
        for (ProductComponentGroup grp : groups) {
            groupLookup.put(grp.ParentProductId + '_' + grp.Name, grp.Id);
        }

            for (Id origId : resolvedOrigCPQOptionsToNewBundle.keySet()) {

                Id parentProductId = resolvedOrigCPQOptionsToNewBundle.get(origId).Id;
                List<SBQQ__ProductOption__c> options = optionMap.get(origId);
                System.debug('options -->> '+ options);
    
                if (options == null) continue;
    
                for (SBQQ__ProductOption__c option : options) {
                    if (option.SBQQ__OptionalSKU__c == null) continue;
    
                    String groupName = COMMON_GROUP_NAME;
                    if (option.SBQQ__Feature__c != null && option.SBQQ__Feature__r != null) {
                        groupName = option.SBQQ__Feature__r.Name;
                    }
    
                    Id groupId = groupLookup.get(parentProductId + '_' + groupName);
                    if (groupId == null) {
                        // Defensive check: skip if no matching group found
                        continue;
                    }
    
                    relatedComponents.add(new ProductRelatedComponent(
                        ParentProductId = parentProductId,
                        ProductComponentGroupId = groupId,
                        ChildProductId = option.SBQQ__OptionalSKU__c,
                        Sequence = (option.SBQQ__Number__c != null) ? Integer.valueOf(option.SBQQ__Number__c) : null,
                        IsDefaultComponent = option.SBQQ__Selected__c,
                        IsComponentRequired = option.SBQQ__Required__c,
                        Quantity = option.SBQQ__Quantity__c,
                        IsQuantityEditable = option.SBQQ__QuantityEditable__c,
                        MinQuantity = option.SBQQ__MinQuantity__c,
                        MaxQuantity = option.SBQQ__MaxQuantity__c,
                        DoesBundlePriceIncludeChild = option.SBQQ__Bundled__c,
                        ProductRelationshipTypeId = relationshipTypeId
                    ));
                }
            }
        return relatedComponents;
    }

    // Update Product2.IsProcessed__c = true
    public static void markProductsProcessed(List<Product2> processedProducts, List<String> errorMessages, List<SObject> failedRecords) {
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
        }
        handleDmlOperation(processedProducts, 'update', 'Mark processed failed', errorMessages, failedRecords);
    }

    // Generic method to handle insert/update DMLs with error logging
    public static void handleDmlOperation(List<SObject> records, String operation, String errorContext, List<String> errorMessages, List<SObject> failedRecords) {
        if (records.isEmpty()) return;
    
        try {
            System.debug('records getting inserted -->> ' + records);
            Database.SaveResult[] results = (operation == 'insert') ? Database.insert(records, false) : Database.update(records, false);
    
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    SObject record = records[i];
                    String objectType = record.getSObjectType().getDescribe().getName();
                    String fullErrorContext = errorContext + ' | Object: ' + objectType ;
                    String CPQErrorRecord = getFailedRecordDetail(record);
                    errorMessages.add(RCA_BatchExceptionLogger.logException(
                        'RCA_ProductCatalogBatch', fullErrorContext,
                        record, results[i].getErrors()[0], CPQErrorRecord
                    ));
                    
                    failedRecords.add(record);
                }
            }
        } catch (Exception e) {
            errorMessages.add(errorContext + ' - Unexpected DML error: ' + e.getMessage());
        }
    }

    //Add details in error email about CPQ records which might be the root cause of the error - 
    public static String getFailedRecordDetail(SObject failedRecord) {
        if (failedRecord == null) return '';
    
        String sObjectName = failedRecord.getSObjectType().getDescribe().getName();
    
        if (sObjectName == 'ProductRelatedComponent') {
            String childProductId = (String)failedRecord.get('ChildProductId');
            return 'Check SBQQ_ProductOption__c record with Optional SKU field: ' + childProductId;
    
        } else if (sObjectName == 'ProductComponentGroup') {
            String groupName = (String)failedRecord.get('Name');
            String parentProductId = (String)failedRecord.get('ParentProductId');
    
            if (groupName != 'Others') {
                List<SBQQ__ProductFeature__c> featureList = [
                    SELECT Id, SBQQ__ConfiguredSKU__c, SBQQ__ConfiguredSKU__r.StockKeepingUnit
                    FROM SBQQ__ProductFeature__c
                    WHERE Name = :groupName
                    LIMIT 1
                ];
    
                if (!featureList.isEmpty()) {
                    SBQQ__ProductFeature__c feature = featureList[0];
                    return 'Check SBQQ_ProductFeature__c with Name: ' + groupName +
                           ', of Product: ' + feature.SBQQ__ConfiguredSKU__c +
                           ', SKU: ' + feature.SBQQ__ConfiguredSKU__r.StockKeepingUnit;
                } else {
                    return 'SBQQ_ProductFeature__c not found for Name: ' + groupName;
                }
            } else {
                return 'Check SBQQ_ProductOption__c record for optional SKU under group "Others".';
            }
        }
        return 'Unknown record type: ' + sObjectName;
    }
    

    //Rollback/Delete all failed parent records created in the  prcess to reduce manual deletion effort- 
    public static void rollbackFailedCPQHierarchy(List<SObject> failedRecords, List<String> errorMessages) {
        Set<Id> productIdsToDelete = new Set<Id>();
    
        // Collect ParentProductIds from failed records
        for (SObject rec : failedRecords) {
            if (rec.get('ParentProductId') != null) {
                productIdsToDelete.add((Id)rec.get('ParentProductId'));
            }
        }
    
        try {
            // Step 1: Delete component groups
            if (!productIdsToDelete.isEmpty()) {
                List<ProductComponentGroup> groupsToDelete = [
                    SELECT Id FROM ProductComponentGroup WHERE ParentProductId IN :productIdsToDelete
                ];

                if (!groupsToDelete.isEmpty()) {
                    delete groupsToDelete;
                    System.debug('Deleted ProductComponentGroups: ' + groupsToDelete.size());
                }
            }
    
            // Step 2: Update parent CPQ products' IsProcessed__c field to false
            getProductsToUpdate(productIdsToDelete);
    
            // Step 3: Delete new bundle products that failed or whose child records failed
            if (!productIdsToDelete.isEmpty()) {
                List<Product2> productsToDelete = [
                    SELECT Id FROM Product2 WHERE Id IN :productIdsToDelete
                ];
                if (!productsToDelete.isEmpty()) {
                    delete productsToDelete;
                    System.debug('Deleted Product2 records: ' + productsToDelete.size());
                }
            }
    
        } catch (Exception e) {
            errorMessages.add('Rollback deletion failed: ' + e.getMessage());
            System.debug('Rollback exception: ' + e.getMessage());
        }
    }
    
    //Update isProcessed__c fields to 'False' for all the failed records - 
    public static void getProductsToUpdate(Set<Id> productIdsToDelete) {
        if (productIdsToDelete == null || productIdsToDelete.isEmpty()) return;
    
        List<Product2> updateOriginalProducts = new List<Product2>();
        List<Product2> productsToUpdate = [
            SELECT Id, StockKeepingUnit FROM Product2 WHERE Id IN :productIdsToDelete
        ];
    
        Set<String> parentCPQProductsSKU = new Set<String>();
        for (Product2 prd : productsToUpdate) {
            if (prd.StockKeepingUnit != null) {
                parentCPQProductsSKU.add(prd.StockKeepingUnit.replace(' - Bundle', ''));
            }
        }
    
        for (Product2 p : [SELECT Id, IsProcessed__c FROM Product2 WHERE StockKeepingUnit IN :parentCPQProductsSKU]) {
            p.IsProcessed__c = false;
            updateOriginalProducts.add(p);
        }
    
        if (!updateOriginalProducts.isEmpty()) {
            update updateOriginalProducts;
            System.debug('Updated products IsProcessed__c to false: ' + updateOriginalProducts.size());
        }
    }
    
    // Email errors to system administrator
    public static void sendErrorNotification(List<String> errorMessages) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA Product Catalog Batch Process Errors');
        mail.setPlainTextBody('RCA_ProductCatalogBatch class failed:\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
    
}