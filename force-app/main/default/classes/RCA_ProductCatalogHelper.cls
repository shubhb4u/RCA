public class RCA_ProductCatalogHelper {

    private static final String DEFAULT_CATEGORY_NAME = 'Default category';
    private static final String REL_TYPE              = 'Bundle';
    private static final String REL_TYPE_NAME         = 'BundleComponent';
    private static final String COMMON_GROUP_NAME     = 'Others';
    private static final Integer DEFAULT_MAX_COMPONENTS = 5;

    // Create a map of CPQ products and their child Product Features - 
    public static Map<Id, List<SBQQ__ProductFeature__c>> fetchFeatures(List<Product2> CPQproducts) {
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        for (Product2 p : CPQproducts) {
            featureMap.put(p.Id, p.SBQQ__Features__r != null
                ? new List<SBQQ__ProductFeature__c>(p.SBQQ__Features__r)
                : new List<SBQQ__ProductFeature__c>());
        }
        return featureMap;
    }

    // Create a map of CPQ products and their child Product Options - 
    public static Map<Id, List<SBQQ__ProductOption__c>> fetchOptions(List<Product2> CPQproducts) {
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = new Map<Id, List<SBQQ__ProductOption__c>>();
        for (Product2 p : CPQproducts) {
            optionMap.put(p.Id, p.SBQQ__Options__r != null
                ? new List<SBQQ__ProductOption__c>(p.SBQQ__Options__r)
                : new List<SBQQ__ProductOption__c>());
        }
        return optionMap;
    }

    //3. Create New bundle products and update existing CPQ products with relevant data - 
    public static void buildProducts( List<Product2> CPQProductsList,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<Product2> newProducts,
        List<Product2> updatedProducts, 
        Map<Id, Product2> origCPQToNewBundle) {

        for (Product2 product : CPQProductsList) {

            //Get Features and Options from CPQ bundle products if they exist- 
            List<SBQQ__ProductFeature__c> features = featureMap.get(product.Id);
            List<SBQQ__ProductOption__c> options = optionMap.get(product.Id);

            Boolean hasFeatures = features != null && !features.isEmpty();
            Boolean hasOptions = options != null && !options.isEmpty();

            String baseName = String.isBlank(product.Name) ? 'PRD' : product.Name;
            String prefix = baseName.length() >= 3
                ? baseName.substring(0,3).toUpperCase()
                : baseName.toUpperCase();

                //If The CPQ product has either Features or Options, create a new bundle product -
                if (hasFeatures || hasOptions) {

                    String skuBase = String.isBlank(product.StockKeepingUnit) ? 
                                                    prefix : product.StockKeepingUnit;
                    
                    // Create a new bundle product - 
                    Product2 bundle = new Product2(
                        Name = product.Name,
                        ProductCode = product.ProductCode + ' - Bundle',
                        IsActive = product.IsActive,
                        ConfigureDuringSale = product.SBQQ__ConfigurationType__c,
                        Type = 'Bundle',
                        StockKeepingUnit = skuBase + ' - Bundle'
                    );
    
                    //Check with Satish if we want to update old CPQ records if missing SKU?
                    if (String.isBlank(product.StockKeepingUnit)) {
                        product.StockKeepingUnit = prefix + ' - CPQ Bundle';
                    }
    
                    //Add new products to be inserted.
                    newProducts.add(bundle); 

                    // Create a map to link the original CPQ product with the new RCA bundle -
                    origCPQToNewBundle.put(product.Id, bundle); 
    
                } else {

                    // Update Standalone CPQ products with relevant RCA fields -  
                    product.ConfigureDuringSale = product.SBQQ__ConfigurationType__c;
                    product.IsSoldOnlyWithOtherProds = product.SBQQ__Component__c;

                    //Check with Satish if we want to update old CPQ records if missing SKU?
                    if (String.isBlank(product.StockKeepingUnit)) {
                        product.StockKeepingUnit = prefix + ' - Standalone';
                    }
                    updatedProducts.add(product);
                }
        }
    }

    //5. Assign default categories to new products and update existing products - 
    public static List<ProductCategoryProduct> assignCategory(List<Product2> products, Id categoryId) {
        List<ProductCategoryProduct> toInsert = new List<ProductCategoryProduct>();
        
        if (products == null || products.isEmpty() || categoryId == null) {
            return toInsert;
        }

        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) {
            if (p.Id != null) productIds.add(p.Id);
        }

        if (productIds.isEmpty()) return toInsert;

        try {
            Set<Id> existingProductIds = new Set<Id>();
            for (ProductCategoryProduct pcp : [
                SELECT ProductId 
                FROM ProductCategoryProduct 
                WHERE ProductCategoryId = :categoryId 
                AND ProductId IN :productIds
            ]) {
                existingProductIds.add(pcp.ProductId);
            }

            for (Id productId : productIds) {
                if (!existingProductIds.contains(productId)) {
                    toInsert.add(new ProductCategoryProduct(
                        ProductId = productId, 
                        ProductCategoryId = categoryId
                    ));
                }
            }
        } catch (Exception e) {
            System.debug('Error checking existing category assignments: ' + e.getMessage());
        }
        
        return toInsert;
    }

    //6. Create ProductComponentGroups for new products - 
    public static List<ProductComponentGroup> buildComponentGroups(Map<Id, Product2> originalToNewMap,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap
    ) {
        List<ProductComponentGroup> groups = new List<ProductComponentGroup>();
        for (Id origId : originalToNewMap.keySet()) {
            Product2 newProd = originalToNewMap.get(origId);

            // Add default 'Others' group
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

    //7. Create ProductRelatedComponents for new products - 
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

    //Get default category Id - 
    public static Id getCategoryId() {
        ProductCategory category = [SELECT Id FROM ProductCategory WHERE Name = :DEFAULT_CATEGORY_NAME LIMIT 1];
        return category != null ? category.Id : null;
    }

    //Get default ProductRelationshipType Id - 
    public static Id getRelationshipTypeId() {
        ProductRelationshipType rel = [SELECT Id,MainProductRoleCat, AssociatedProductRoleCat  FROM ProductRelationshipType WHERE AssociatedProductRoleCat =:REL_TYPE_NAME  AND MainProductRoleCat = :REL_TYPE LIMIT 1];
        return rel != null ? rel.Id : null;
    }

    //Create a message to include failed records details -
    public static String formatDmlError(String context, SObject record, Database.Error error, List<String> fields) {
        List<String> parts = new List<String>();
        Map<String, Object> fieldMap = record.getPopulatedFieldsAsMap();
        
        // Add field values
        for(String field : fields) {
            Object value = fieldMap.containsKey(field) ? fieldMap.get(field) : 'N/A';
            parts.add(field);
            parts.add(String.valueOf(value));
        }
        
        // Add error details
        parts.add(error.getMessage());
        parts.add(String.join(error.getFields(), ', '));
        
        // Build template dynamically
        String template = context + ':\n';
        Integer index = 0;
        for(Integer i = 0; i < fields.size(); i++) {
            template += '  {0}: {1}\n'.replace('0', String.valueOf(index++)).replace('1', String.valueOf(index++));
        }
        template += '  Error: {' + index++ + '}\n' +
                    '  Fields: {' + index++ + '}';
        
        return String.format(template, parts);
    }
}