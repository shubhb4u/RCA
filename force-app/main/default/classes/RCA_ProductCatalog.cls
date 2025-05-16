global class RCA_ProductCatalog implements Database.Batchable<SObject> {

    //Give logical values for min and max quantities, as well as default quantity should fall between these range
    //Give proper name for Common group
    // ProductRelationshipType should be dynamic, it is harcoded now
    //MaxBundleComponents is hadrcoded , fix it
    // Handle SKU Prefix/suffix in a better way
    // Assign categories ot old CPQ products -> Review this later.

    private List<Id> productIds;

    global RCA_ProductCatalog() {}

    global RCA_ProductCatalog(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {

        String baseQuery = 
            'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c, StockKeepingUnit, ' +
            '(SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, SBQQ__Required__c, SBQQ__Quantity__c, SBQQ__Feature__c, SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, SBQQ__ConfiguredSKU__c, SBQQ__Feature__r.Name, SBQQ__Bundled__c FROM SBQQ__Options__r), ' +
            '(SELECT Id, Name, SBQQ__ConfiguredSKU__r.StockKeepingUnit, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c FROM SBQQ__Features__r) ' +
            'FROM Product2';

        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' WHERE Id IN :productIds';
        }

        System.debug('Start method executing with query: ' + baseQuery);
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext bc, List<Product2> scope) {

        System.debug('Execute called with scope size:-->> ' + scope.size());

        List<Product2> newProductList = new List<Product2>();
        List<Product2> updateProductList = new List<Product2>();
        Map<Id, List<SBQQ__ProductFeature__c>> oldFeatureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        Map<Id, List<SBQQ__ProductOption__c>> oldOptionsMap = new Map<Id, List<SBQQ__ProductOption__c>>();
        Map<Id, Product2> originalIdToNewProductMap = new Map<Id, Product2>(); // Track original to new product

        // Query ProductCategory and RecordType (same as before)
        List<ProductCategory> category = [SELECT Id FROM ProductCategory WHERE Name = 'default category' LIMIT 1];
        if(category.isEmpty()) { 
            System.debug('Empty category'+ category);
            return;
         }

        List<RecordType> rtList = [SELECT Id FROM RecordType WHERE Name = 'Commercial' AND SObjectType = 'Product2' LIMIT 1];
        if(rtList.isEmpty()) { 
            System.debug('Empty rtList'+ rtList);
            return;
         }

        Id commercialRecordTypeId = rtList[0].Id;

        // 1. Process CPQ Products
        for (Product2 cpqProduct : scope) {
            // Populate feature/option maps using original product Id
            oldFeatureMap.put(cpqProduct.Id, cpqProduct.SBQQ__Features__r != null ? cpqProduct.SBQQ__Features__r : new List<SBQQ__ProductFeature__c>());
            oldOptionsMap.put(cpqProduct.Id, cpqProduct.SBQQ__Options__r != null ? cpqProduct.SBQQ__Options__r : new List<SBQQ__ProductOption__c>());

            Boolean hasFeatures = !oldFeatureMap.get(cpqProduct.Id).isEmpty();
            Boolean hasOptions = !oldOptionsMap.get(cpqProduct.Id).isEmpty();

            if (hasFeatures || hasOptions) {
                // Create new RCA bundle product
                Product2 newProduct = new Product2(
                    Name = cpqProduct.Name,
                    ProductCode = cpqProduct.ProductCode,
                    IsActive = cpqProduct.IsActive,
                    ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c,
                    Type = 'Bundle',
                    RecordTypeId = commercialRecordTypeId
                );

                // Generate SKU
                if (String.isBlank(cpqProduct.StockKeepingUnit)) {
                    String prefix = cpqProduct.Name.length() >= 3 ? cpqProduct.Name.substring(0,3).toUpperCase() : cpqProduct.Name.toUpperCase();
                    newProduct.StockKeepingUnit = prefix + ' - Bundle';
                    cpqProduct.StockKeepingUnit = prefix + ' - CPQ Bundle';
                } else {
                    newProduct.StockKeepingUnit = cpqProduct.StockKeepingUnit + ' - Bundle';
                }

                newProductList.add(newProduct);
                originalIdToNewProductMap.put(cpqProduct.Id, newProduct); // Link original to new product
                updateProductList.add(cpqProduct); 
            } else {
                // Update standalone product as RCA -
                cpqProduct.ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c;
                cpqProduct.IsSoldOnlyWithOtherProds = cpqProduct.SBQQ__Component__c;
                cpqProduct.RecordTypeId = commercialRecordTypeId; // Set RCA record type

                if (String.isBlank(cpqProduct.StockKeepingUnit)) {
                    String prefix = cpqProduct.Name.length() >= 3 ? cpqProduct.Name.substring(0,3).toUpperCase() : cpqProduct.Name.toUpperCase();
                    cpqProduct.StockKeepingUnit = prefix + ' - Standalone';
                }
                updateProductList.add(cpqProduct);
            }
        }

        // Insert/update products (same as before)
        try {
            insert newProductList;
            update updateProductList;
        } catch (Exception e) { 
             System.debug('Error during insert and update ->> ' + e.getMessage());
         }


        // 2. Assign ProductCategory — but skip ones that already exist
        Set<Id> allProdIds = new Set<Id>();
        for (Product2 p : newProductList)    allProdIds.add(p.Id);
        for (Product2 p : updateProductList) allProdIds.add(p.Id); //Review this later.

        // Query existing links
        Map<Id, Set<Id>> existingLinks = new Map<Id, Set<Id>>();
        for (ProductCategoryProduct e : [SELECT ProductId, ProductCategoryId FROM ProductCategoryProduct 
                                        WHERE ProductCategoryId = :category[0].Id
                                        AND ProductId IN :allProdIds]) {
                if (!existingLinks.containsKey(e.ProductId)) {
                    existingLinks.put(e.ProductId, new Set<Id>{ e.ProductCategoryId });
                } else {
                    existingLinks.get(e.ProductId).add(e.ProductCategoryId);
                }
            } 

            // Build only the *new* links
            List<ProductCategoryProduct> links = new List<ProductCategoryProduct>();
            for (Id pid : allProdIds) {
                if (existingLinks.containsKey(pid)
                    && existingLinks.get(pid).contains(category[0].Id)) {
                    continue; 
                }
                links.add(new ProductCategoryProduct(
                    ProductId        = pid,
                    ProductCategoryId = category[0].Id
                ));
            }

            // Insert any new links
            if (!links.isEmpty()) {
                try {
                    insert links;
                } catch (Exception ex) {
                    System.debug('Error inserting ProductCategoryProduct links: ' + ex.getMessage());
                }
            }


        // 3. Create ProductComponentGroups using original Id mapping
        List<ProductComponentGroup> componentGroups = new List<ProductComponentGroup>();

        for (Id originalId : originalIdToNewProductMap.keySet()) {

            Product2 newProduct = originalIdToNewProductMap.get(originalId);
            List<SBQQ__ProductFeature__c> features = oldFeatureMap.get(originalId);

            // Always add a "Common" group
            componentGroups.add(new ProductComponentGroup(
                Name = 'Common',
                MinBundleComponents = 0,
                // MaxBundleComponents = 10, //Hardcoded, decided later , it should be greater than 0
                Sequence = 1,
                ParentProductId = newProduct.Id
            ));

            // Add feature-based groups if they exist
            if (features != null && !features.isEmpty()) {
                for (SBQQ__ProductFeature__c feat : features) {
                    componentGroups.add(new ProductComponentGroup(
                        Name = feat.Name,
                        MinBundleComponents = (Integer) feat.SBQQ__MinOptionCount__c,
                        MaxBundleComponents = (Integer) feat.SBQQ__MaxOptionCount__c,
                        Sequence = (Integer) feat.SBQQ__Number__c,
                        ParentProductId = newProduct.Id
                    ));
                }
            }
        }

        // Insert new component groups
        try {
            if (!componentGroups.isEmpty()) {
                insert componentGroups;
                System.debug('Inserted component groups: ' + componentGroups.size());
            }
        } catch (Exception e) {
            System.debug('Error inserting ProductComponentGroup: ' + e.getMessage());
        }
        

        //4. Create ProductRelatedComponent for newProductList created above, taking reference from SBQQ__ProductOption__c records of CPQ Products - 

        //Create a map of New ComponentGroups created and their Ids - 
        Map<String, Id> pcMap = new Map<String, Id>();
        if (!componentGroups.isEmpty()) {
            for (ProductComponentGroup pc : componentGroups) {
                // Composite key: ParentProductId + '_' + GroupName
                pcMap.put(pc.ParentProductId + '_' + pc.Name, pc.Id);
            }
        }

        // Get the id of ProductRelationshipType required field - 
        List<ProductRelationshipType> relType = [SELECT Id FROM ProductRelationshipType 
            WHERE Name = 'Bundle to Bundle Component Relationship' 
            LIMIT 1
        ];
        if (relType.isEmpty()) {
            System.debug('Required ProductRelationshipType not found.');
            return;
        }
        Id componentRelTypeId = relType[0].Id;

        List<ProductRelatedComponent> relatedComponentList = new List<ProductRelatedComponent>();

        for (Id originalId : originalIdToNewProductMap.keySet()) {
            
            Product2 newProduct = originalIdToNewProductMap.get(originalId);
            List<SBQQ__ProductOption__c> options = oldOptionsMap.get(originalId);
            System.debug('options-->> ' + options);

            if (options != null && !options.isEmpty()) {
                for (SBQQ__ProductOption__c op : options) {

                    String featureName = (op.SBQQ__Feature__r != null) ? op.SBQQ__Feature__r.Name : 'Common';
                    String compositeKey = newProduct.Id + '_' + featureName;

                    relatedComponentList.add(new ProductRelatedComponent(
                        ParentProductId = newProduct.Id,
                        ProductComponentGroupId = pcMap.get(compositeKey),
                        ChildProductId = op.SBQQ__OptionalSKU__c,
                        Sequence = (Integer) op.SBQQ__Number__c,
                        IsDefaultComponent = op.SBQQ__Selected__c,
                        IsComponentRequired = op.SBQQ__Required__c,
                        Quantity = op.SBQQ__Quantity__c,
                        IsQuantityEditable = op.SBQQ__QuantityEditable__c,
                        MinQuantity = op.SBQQ__MinQuantity__c,
                        MaxQuantity = op.SBQQ__MaxQuantity__c,
                        DoesBundlePriceIncludeChild = op.SBQQ__Bundled__c,
                        ProductRelationshipTypeId = componentRelTypeId //Change this depending on mapping type later
                    ));
                }
            }
        }

        try {
            if (!relatedComponentList.isEmpty()) {
                insert relatedComponentList;
                System.debug('Inserted related components:-->> ' + relatedComponentList.size());
            }
        } catch (Exception e) {
            System.debug('Error inserting ProductRelatedComponent: ' + e.getMessage());
        }
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed.');
    
    }
}