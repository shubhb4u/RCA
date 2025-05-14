public with sharing class ProductMigrationCPQtoRLMHelper {

    private Id commercialRecordTypeId;
    private Id defaultCategoryId;

    public ProductMigrationCPQtoRLMHelper() {
        commercialRecordTypeId = [SELECT Id FROM RecordType WHERE Name = 'Commercial' AND SObjectType = 'Product2' LIMIT 1].Id;
        defaultCategoryId = [SELECT Id FROM ProductCategory WHERE Name = 'default category' LIMIT 1].Id;
    }

    public List<Product2> createNewProducts(List<Product2> scope) {
        List<Product2> newProducts = new List<Product2>();

        for (Product2 cpqProduct : scope) {
            if ((cpqProduct.SBQQ__Options__r != null && !cpqProduct.SBQQ__Options__r.isEmpty()) ||
                (cpqProduct.SBQQ__Features__r != null && !cpqProduct.SBQQ__Features__r.isEmpty())) {

                Product2 newProduct = new Product2();
                newProduct.Name = cpqProduct.Name;
                newProduct.ProductCode = cpqProduct.ProductCode;
                newProduct.IsActive = cpqProduct.IsActive;
                newProduct.ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c;
                newProduct.Type = 'Bundle';
                newProduct.StockKeepingUnit = cpqProduct.StockKeepingUnit + 'Bundle';
                newProduct.RecordTypeId = commercialRecordTypeId;
                newProducts.add(newProduct);
            }
        }

        return newProducts;
    }

    public List<Product2> updateExistingProducts(List<Product2> scope) {
        List<Product2> updateProducts = new List<Product2>();

        for (Product2 cpqProduct : scope) {
            if ((cpqProduct.SBQQ__Options__r == null || cpqProduct.SBQQ__Options__r.isEmpty()) &&
                (cpqProduct.SBQQ__Features__r == null || cpqProduct.SBQQ__Features__r.isEmpty())) {

                cpqProduct.ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c;
                cpqProduct.IsSoldOnlyWithOtherProds = cpqProduct.SBQQ__Component__c;
                updateProducts.add(cpqProduct);
            }
        }

        return updateProducts;
    }

    public List<ProductCategoryProduct> createProductCategoryLinks(List<Product2> newProducts, List<Product2> updateProducts) {
        List<ProductCategoryProduct> categoryLinks = new List<ProductCategoryProduct>();

        for (Product2 product : newProducts) {
            if (product.IsSoldOnlyWithOtherProds == false) {
                categoryLinks.add(createCategoryProductLink(product.Id));
            }
        }

        for (Product2 product : updateProducts) {
            if (product.IsSoldOnlyWithOtherProds == false) {
                categoryLinks.add(createCategoryProductLink(product.Id));
            }
        }

        return categoryLinks;
    }

    private ProductCategoryProduct createCategoryProductLink(Id productId) {
        ProductCategoryProduct link = new ProductCategoryProduct();
        link.ProductId = productId;
        link.ProductCategoryId = defaultCategoryId;
        return link;
    }

    public List<ProductComponentGroup> createProductComponentGroups(List<Product2> newProducts) {
        List<ProductComponentGroup> componentGroups = new List<ProductComponentGroup>();

        for (Product2 product : newProducts) {
            List<SBQQ__ProductFeature__c> featureList = [
                SELECT Name, SBQQ__ConfiguredSKU__r.Name, SBQQ__MinOptionCount__c,
                       SBQQ__MaxOptionCount__c, SBQQ__Number__c
                FROM SBQQ__ProductFeature__c
                WHERE SBQQ__ConfiguredSKU__r.Name = :product.Name
            ];

            for (SBQQ__ProductFeature__c feature : featureList) {
                ProductComponentGroup componentGroup = new ProductComponentGroup();
                componentGroup .Name = feature.Name;
                componentGroup .MinBundleComponents = (Integer)feature.SBQQ__MinOptionCount__c;
                componentGroup .MaxBundleComponents = (Integer)feature.SBQQ__MaxOptionCount__c;
                componentGroup .Sequence = (Integer)feature.SBQQ__Number__c;
                componentGroup .ParentProductId = product.Id;
                componentGroups.add(componentGroup );
            }
        }

        return componentGroups;
    }
}