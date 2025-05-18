public class RCA_ProductCatalogHelper {

    private static final String DEFAULT_CATEGORY_NAME = 'default category';
    private static final String COMMERCIAL_RT_NAME    = 'Commercial';
    private static final String REL_TYPE_NAME         = 'Bundle to Bundle Component Relationship';
    private static final String COMMON_GROUP_NAME     = 'Common';
    private static final Integer DEFAULT_MAX_COMPONENTS = 5;

    public static Map<Id, List<SBQQ__ProductFeature__c>> fetchFeatures(List<Product2> products) {
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        for (Product2 p : products) {
            featureMap.put(p.Id, p.SBQQ__Features__r != null
                ? new List<SBQQ__ProductFeature__c>(p.SBQQ__Features__r)
                : new List<SBQQ__ProductFeature__c>());
        }
        return featureMap;
    }

    public static Map<Id, List<SBQQ__ProductOption__c>> fetchOptions(List<Product2> products) {
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = new Map<Id, List<SBQQ__ProductOption__c>>();
        for (Product2 p : products) {
            optionMap.put(p.Id, p.SBQQ__Options__r != null
                ? new List<SBQQ__ProductOption__c>(p.SBQQ__Options__r)
                : new List<SBQQ__ProductOption__c>());
        }
        return optionMap;
    }

    public static Map<Id, Product2> buildProducts(
        List<Product2> scope,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<Product2> newProducts,
        List<Product2> updatedProducts,
        Id recordTypeId
    ) {
        Map<Id, Product2> originalToNewMap = new Map<Id, Product2>();

        for (Product2 product : scope) {

            List<SBQQ__ProductFeature__c> features = featureMap.get(product.Id);
            List<SBQQ__ProductOption__c> options = optionMap.get(product.Id);

            Boolean hasFeatures = features != null && !features.isEmpty();
            Boolean hasOptions = options != null && !options.isEmpty();

            String baseName = String.isBlank(product.Name) ? 'PRD' : product.Name;
            String prefix = baseName.length() >= 3
                ? baseName.substring(0,3).toUpperCase()
                : baseName.toUpperCase();

            if (hasFeatures || hasOptions) {
                // Create a new bundle product
                String skuBase = String.isBlank(product.StockKeepingUnit) ? prefix : product.StockKeepingUnit;
                Product2 bundle = new Product2(
                    Name = product.Name,
                    ProductCode = product.ProductCode,
                    IsActive = product.IsActive,
                    ConfigureDuringSale = product.SBQQ__ConfigurationType__c,
                    Type = 'Bundle',
                    RecordTypeId = recordTypeId,
                    StockKeepingUnit = skuBase + ' - Bundle'
                );

                if (String.isBlank(product.StockKeepingUnit)) {
                    product.StockKeepingUnit = prefix + ' - CPQ Bundle';
                }

                newProducts.add(bundle);
                updatedProducts.add(product);
                originalToNewMap.put(product.Id, bundle);

            } else {
                // Update product as standalone
                product.ConfigureDuringSale = product.SBQQ__ConfigurationType__c;
                product.IsSoldOnlyWithOtherProds = product.SBQQ__Component__c;
                product.RecordTypeId = recordTypeId;
                if (String.isBlank(product.StockKeepingUnit)) {
                    product.StockKeepingUnit = prefix + ' - Standalone';
                }
                updatedProducts.add(product);
            }
        }
        return originalToNewMap;
    }

    public static void assignCategory(Set<Id> productIds, Id categoryId) {

        if (categoryId == null || productIds.isEmpty()) return;

        Set<Id> existingProductIds = new Set<Id>();
        for (ProductCategoryProduct pcp : [SELECT ProductId FROM ProductCategoryProduct
                                            WHERE ProductCategoryId = :categoryId
                                            AND ProductId IN :productIds]) {
            existingProductIds.add(pcp.ProductId);
        }

        List<ProductCategoryProduct> toInsert = new List<ProductCategoryProduct>();
        for (Id productId : productIds) {
            if (!existingProductIds.contains(productId)) {
                toInsert.add(new ProductCategoryProduct(ProductId = productId, ProductCategoryId = categoryId));
            }
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    public static List<ProductComponentGroup> buildComponentGroups(Map<Id, Product2> originalToNewMap,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap
    ) {
        List<ProductComponentGroup> groups = new List<ProductComponentGroup>();
        for (Id origId : originalToNewMap.keySet()) {
            Product2 newProd = originalToNewMap.get(origId);

            // Add default 'Common' group
            groups.add(new ProductComponentGroup(
                ParentProductId = newProd.Id,
                Name = COMMON_GROUP_NAME,
                MinBundleComponents = 0,
                MaxBundleComponents = DEFAULT_MAX_COMPONENTS,
                Sequence = 1
            ));

            // Add groups for each feature
            List<SBQQ__ProductFeature__c> features = featureMap.get(origId);
            if (features != null) {
                for (SBQQ__ProductFeature__c feature : features) {
                    if (feature != null) {
                        groups.add(new ProductComponentGroup(
                            ParentProductId = newProd.Id,
                            Name = feature.Name,
                            MinBundleComponents = (Integer)feature.SBQQ__MinOptionCount__c,
                            MaxBundleComponents = feature.SBQQ__MaxOptionCount__c != null
                                ? (Integer)feature.SBQQ__MaxOptionCount__c
                                : DEFAULT_MAX_COMPONENTS,
                            Sequence = (Integer)feature.SBQQ__Number__c
                        ));
                    }
                }
            }
        }
        return groups;
    }

    public static List<ProductRelatedComponent> buildRelatedComponents(
        Map<Id, Product2> originalToNewMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<ProductComponentGroup> groups,
        Id relationshipTypeId
    ) {
        Map<String, Id> groupLookup = new Map<String, Id>();
        for (ProductComponentGroup grp : groups) {
            groupLookup.put(grp.ParentProductId + '_' + grp.Name, grp.Id);
        }

        List<ProductRelatedComponent> relatedComponents = new List<ProductRelatedComponent>();
        for (Id origId : originalToNewMap.keySet()) {
            Id parentProductId = originalToNewMap.get(origId).Id;
            List<SBQQ__ProductOption__c> options = optionMap.get(origId);

            if (options == null) continue;

            for (SBQQ__ProductOption__c option : options) {
                if (option.SBQQ__OptionalSKU__c == null) continue;

                String groupName = option.SBQQ__Feature__c != null && option.SBQQ__Feature__r != null
                    ? option.SBQQ__Feature__r.Name
                    : COMMON_GROUP_NAME;

                relatedComponents.add(new ProductRelatedComponent(
                    ParentProductId = parentProductId,
                    ProductComponentGroupId = groupLookup.get(parentProductId + '_' + groupName),
                    ChildProductId = option.SBQQ__OptionalSKU__c,
                    Sequence = (Integer)option.SBQQ__Number__c,
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

    public static Id getCategoryId() {
        ProductCategory category = [SELECT Id FROM ProductCategory WHERE Name = :DEFAULT_CATEGORY_NAME LIMIT 1];
        return category != null ? category.Id : null;
    }

    public static Id getRecordTypeId() {
        RecordType rt = [SELECT Id FROM RecordType WHERE Name = :COMMERCIAL_RT_NAME AND SObjectType = 'Product2' LIMIT 1];
        return rt != null ? rt.Id : null;
    }

    public static Id getRelationshipTypeId() {
        ProductRelationshipType rel = [SELECT Id FROM ProductRelationshipType WHERE Name = :REL_TYPE_NAME LIMIT 1];
        return rel != null ? rel.Id : null;
    }
}
