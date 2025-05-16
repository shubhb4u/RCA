public class RCA_ProductCatalogHelper {

    private static final String DEFAULT_CATEGORY_NAME   = 'default category';
    private static final String COMMERCIAL_RT_NAME      = 'Commercial';
    private static final String REL_TYPE_NAME           = 'Bundle to Bundle Component Relationship';
    private static final String COMMON_GROUP_NAME       = 'Common';
    private static final Integer DEFAULT_MAX_COMPONENTS = 5;

    public static Map<Id, List<SBQQ__ProductFeature__c>> fetchFeatures(List<Product2> scope) {
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = new Map<Id, List<SBQQ__ProductFeature__c>>();
        for (Product2 p : scope) {
            featureMap.put(p.Id,
                p.SBQQ__Features__r != null
                  ? new List<SBQQ__ProductFeature__c>(p.SBQQ__Features__r)
                  : new List<SBQQ__ProductFeature__c>()
            );
        }
        return featureMap;
    }

    public static Map<Id, List<SBQQ__ProductOption__c>> fetchOptions(List<Product2> scope) {
        Map<Id, List<SBQQ__ProductOption__c>> optionMap = new Map<Id, List<SBQQ__ProductOption__c>>();
        for (Product2 p : scope) {
            optionMap.put(p.Id,
                p.SBQQ__Options__r != null
                  ? new List<SBQQ__ProductOption__c>(p.SBQQ__Options__r)
                  : new List<SBQQ__ProductOption__c>()
            );
        }
        return optionMap;
    }

    public static Map<Id, Product2> buildProducts(
        List<Product2> scope,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<Product2> newProds,
        List<Product2> updProds,
        Id rtId
    ) {
        Map<Id, Product2> origToNew = new Map<Id, Product2>();
        for (Product2 p : scope) {
            List<SBQQ__ProductFeature__c> feats = featureMap.get(p.Id);
            List<SBQQ__ProductOption__c> opts  = optionMap.get(p.Id);
            Boolean hasFeat = feats != null && !feats.isEmpty();
            Boolean hasOpt  = opts  != null && !opts.isEmpty();

            String baseName = String.isBlank(p.Name) ? 'PRD' : p.Name;
            String prefix   = baseName.length() >= 3
                ? baseName.substring(0,3).toUpperCase()
                : baseName.toUpperCase();

            if (hasFeat || hasOpt) {
                String skuBase = String.isBlank(p.StockKeepingUnit) ? prefix : p.StockKeepingUnit;
                Product2 bundle = new Product2(
                    Name                = p.Name,
                    ProductCode         = p.ProductCode,
                    IsActive            = p.IsActive,
                    ConfigureDuringSale = p.SBQQ__ConfigurationType__c,
                    Type                = 'Bundle',
                    RecordTypeId        = rtId,
                    StockKeepingUnit    = skuBase + ' - Bundle'
                );
                if (String.isBlank(p.StockKeepingUnit)) {
                    p.StockKeepingUnit = prefix + ' - CPQ Bundle';
                }
                newProds.add(bundle);
                updProds.add(p);
                origToNew.put(p.Id, bundle);

            } else {
                p.ConfigureDuringSale      = p.SBQQ__ConfigurationType__c;
                p.IsSoldOnlyWithOtherProds = p.SBQQ__Component__c;
                p.RecordTypeId             = rtId;
                if (String.isBlank(p.StockKeepingUnit)) {
                    p.StockKeepingUnit = prefix + ' - Standalone';
                }
                updProds.add(p);
            }
        }
        return origToNew;
    }

    public static void assignCategory(Set<Id> prodIds, Id catId) {
        if (catId == null || prodIds.isEmpty()) return;
        Set<Id> existing = new Set<Id>();
        for (ProductCategoryProduct pcp : [SELECT ProductId FROM ProductCategoryProduct WHERE           ProductCategoryId = :catId
               AND ProductId IN :prodIds ]) {
            existing.add(pcp.ProductId);
        }
        List<ProductCategoryProduct> toInsert = new List<ProductCategoryProduct>();
        for (Id pid : prodIds) {
            if (!existing.contains(pid)) {
                toInsert.add(new ProductCategoryProduct(
                    ProductId = pid,
                    ProductCategoryId = catId
                ));
            }
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, false);
        }
    }

    public static List<ProductComponentGroup> buildComponentGroups(
        Map<Id, Product2> origToNew,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap
    ) {
        List<ProductComponentGroup> groups = new List<ProductComponentGroup>();
        for (Id origId : origToNew.keySet()) {
            Id newId = origToNew.get(origId).Id;
            groups.add(new ProductComponentGroup(
                ParentProductId     = newId,
                Name                = COMMON_GROUP_NAME,
                MinBundleComponents = 0,
                MaxBundleComponents = DEFAULT_MAX_COMPONENTS,
                Sequence            = 1
            ));
            for (SBQQ__ProductFeature__c f : featureMap.get(origId)) {
                if (f != null) {
                    groups.add(new ProductComponentGroup(
                        ParentProductId     = newId,
                        Name                = f.Name,
                        MinBundleComponents = (Integer)f.SBQQ__MinOptionCount__c,
                        MaxBundleComponents = f.SBQQ__MaxOptionCount__c != null
                                                ? (Integer)f.SBQQ__MaxOptionCount__c
                                                : DEFAULT_MAX_COMPONENTS,
                        Sequence            = (Integer)f.SBQQ__Number__c
                    ));
                }
            }
        }
        return groups;
    }

    public static List<ProductRelatedComponent> buildRelatedComponents(
        Map<Id, Product2> origToNew,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<ProductComponentGroup> groups,
        Id relTypeId
    ) {
        Map<String, Id> groupLookup = new Map<String, Id>();
        for (ProductComponentGroup g : groups) {
            groupLookup.put(g.ParentProductId + '_' + g.Name, g.Id);
        }

        List<ProductRelatedComponent> rels = new List<ProductRelatedComponent>();

        for (Id origId : origToNew.keySet()) {

            Id parentId = origToNew.get(origId).Id;
            for (SBQQ__ProductOption__c o : optionMap.get(origId)) {

                if (o.SBQQ__OptionalSKU__c == null) continue;
                String featureName = o.SBQQ__Feature__c != null
                                   ? o.SBQQ__Feature__r.Name
                                   : COMMON_GROUP_NAME;
                rels.add(new ProductRelatedComponent(
                    ParentProductId             = parentId,
                    ProductComponentGroupId     = groupLookup.get(parentId+'_'+featureName),
                    ChildProductId              = o.SBQQ__OptionalSKU__c,
                    Sequence                    = (Integer)o.SBQQ__Number__c,
                    IsDefaultComponent          = o.SBQQ__Selected__c,
                    IsComponentRequired         = o.SBQQ__Required__c,
                    Quantity                    = o.SBQQ__Quantity__c,
                    IsQuantityEditable          = o.SBQQ__QuantityEditable__c,
                    MinQuantity                 = o.SBQQ__MinQuantity__c,
                    MaxQuantity                 = o.SBQQ__MaxQuantity__c,
                    DoesBundlePriceIncludeChild = o.SBQQ__Bundled__c,
                    ProductRelationshipTypeId   = relTypeId
                ));
            }
        }
        return rels;
    }

    public static Id getCategoryId() {
        ProductCategory cat = [
            SELECT Id
              FROM ProductCategory
             WHERE Name = :DEFAULT_CATEGORY_NAME
             LIMIT 1
        ];
        return cat == null ? null : cat.Id;
    }

    public static Id getRecordTypeId() {
        RecordType rt = [
            SELECT Id
              FROM RecordType
             WHERE Name = :COMMERCIAL_RT_NAME
               AND SObjectType = 'Product2'
             LIMIT 1
        ];
        return rt == null ? null : rt.Id;
    }

    public static Id getRelationshipTypeId() {
        ProductRelationshipType rel = [
            SELECT Id
              FROM ProductRelationshipType
             WHERE Name = :REL_TYPE_NAME
             LIMIT 1
        ];
        return rel == null ? null : rel.Id;
    }

    public static Set<Id> getAllIds(List<Product2> newP, List<Product2> updP) {
        Set<Id> ids = new Set<Id>();
        for (Product2 p : newP) if (p.Id != null) ids.add(p.Id);
        for (Product2 p : updP) if (p.Id != null) ids.add(p.Id);
        return ids;
    }
}
