public class RCA_ProductCatalogBatchHelper {

    private static final String DEFAULT_CATEGORY_NAME = 'Default category';
    private static final String REL_TYPE              = 'Bundle';
    private static final String REL_TYPE_NAME         = 'BundleComponent';
    private static final String COMMON_GROUP_NAME     = 'Others';
    private static final Integer DEFAULT_MAX_COMPONENTS = 5;

    // 1. Fetch features from related child records (expecting loaded relationship)
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
        Map<Id, Map<Id, Product2>> origCPQToNewBundleMap
    ) {
        for (Product2 product : CPQProductsList) {

            List<SBQQ__ProductFeature__c> features = featureMap.get(product.Id);
            List<SBQQ__ProductOption__c> options = optionMap.get(product.Id);

            Boolean hasFeatures = features != null && !features.isEmpty();
            Boolean hasOptions = options != null && !options.isEmpty();

            String baseName = String.isBlank(product.Name) ? 'PRD' : product.Name;
            String prefix = baseName.length() >= 3
                ? baseName.substring(0,3).toUpperCase()
                : baseName.toUpperCase();

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

                // Map original product Id to a map with new bundle product(s)
                if (!origCPQToNewBundleMap.containsKey(product.Id)) {
                    origCPQToNewBundleMap.put(product.Id, new Map<Id, Product2>());
                }
                origCPQToNewBundleMap.get(product.Id).put(product.Id, bundle);
            } else {
                // Update standalone CPQ products with relevant RCA fields
                product.SBQQ__ConfigurationType__c = product.SBQQ__ConfigurationType__c; // This line seems redundant but left as is
                product.IsSoldOnlyWithOtherProds = product.SBQQ__Component__c;
                updatedProducts.add(product);
            }
        }
    }

    /**
     * 4. Assign default categories to new and updated products, avoiding duplicates
     */
    public static void assignCategory(
        List<Product2> updatedProducts,
        List<Product2> newProducts,
        List<ProductCategoryProduct> toInsert,
        Id categoryId) {

        List<Product2> allProducts = new List<Product2>();
        allProducts.addAll(updatedProducts);
        allProducts.addAll(newProducts);

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : allProducts) {
            if (p.Id != null) productIds.add(p.Id);
        }

        Set<Id> existingProductIds = new Set<Id>();
        for (ProductCategoryProduct pcp : [
            SELECT ProductId 
            FROM ProductCategoryProduct 
            WHERE ProductCategoryId = :categoryId 
            AND ProductId IN :productIds
        ]) {
            existingProductIds.add(pcp.ProductId);
        }

        for (Product2 p : allProducts) {
            if (!existingProductIds.contains(p.Id)) {
                toInsert.add(new ProductCategoryProduct(
                    ProductId = p.Id,
                    ProductCategoryId = categoryId
                ));
            }
        }
    }

    /**
     * 5. Create ProductComponentGroups with default group + feature groups
     * Accepts resolved bundles map: Map<Id (origProductId), Product2 (new bundle)>
     */
    public static List<ProductComponentGroup> buildComponentGroups(
        Map<Id, Product2> originalToNewMap,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap
    ) {
        List<ProductComponentGroup> groups = new List<ProductComponentGroup>();
        for (Id origId : originalToNewMap.keySet()) {
            Product2 newProd = originalToNewMap.get(origId);

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
        Map<Id, Product2> originalToNewMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<ProductComponentGroup> groups,
        Id relationshipTypeId
    ) {


        List<ProductRelatedComponent> relatedComponents = new List<ProductRelatedComponent>();

        Map<String, Id> groupLookup = new Map<String, Id>();
        for (ProductComponentGroup grp : groups) {
            groupLookup.put(grp.ParentProductId + '_' + grp.Name, grp.Id);
        }

        System.debug('originalToNewMap -->> '+ originalToNewMap);

            for (Id origId : originalToNewMap.keySet()) {

                Id parentProductId = originalToNewMap.get(origId).Id;
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

                System.debug('relatedComponents -->> '+ relatedComponents);
            }
        
        
        return relatedComponents;
    }

    // 7. Get default category Id, returns null if not found (safe)
    public static Id getCategoryId() {
        List<ProductCategory> categories = [SELECT Id FROM ProductCategory WHERE Name = :DEFAULT_CATEGORY_NAME LIMIT 1];
        return categories.isEmpty() ? null : categories[0].Id;
    }

    // 8. Get default ProductRelationshipType Id, returns null if not found (safe)
    public static Id getRelationshipTypeId() {
        List<ProductRelationshipType> rels = [
            SELECT Id, MainProductRoleCat, AssociatedProductRoleCat
            FROM ProductRelationshipType
            WHERE AssociatedProductRoleCat = :REL_TYPE_NAME
            AND MainProductRoleCat = :REL_TYPE
            LIMIT 1
        ];
        return rels.isEmpty() ? null : rels[0].Id;
    }

    
}
