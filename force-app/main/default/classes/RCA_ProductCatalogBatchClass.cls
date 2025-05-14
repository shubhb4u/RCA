global class RCA_ProductCatalogBatchClass implements Database.Batchable<SObject> {


    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, SBQQ__Component__c,StockKeepingUnit,(SELECT Id, SBQQ__Bundled__c FROM SBQQ__Options__r),(SELECT Id FROM SBQQ__Features__r) FROM Product2'
        );
    }

    global void execute(Database.BatchableContext bc, List<Product2> scope) {

        List<ProductCategory> category = [SELECT Id FROM ProductCategory WHERE Name = 'default category'];
        List<Product2> newProductList = new List<Product2>();
        List<Product2> updateProductList = new List<Product2>();

        List<RecordType> recordTypeIdList = [
            SELECT Id FROM RecordType WHERE Name = 'Commercial' AND SObjectType = 'Product2'
        ];
        Id commercialRecordTypeId = recordTypeIdList.isEmpty() ? null : recordTypeIdList[0].Id;

        for (Product2 cpqProduct : scope) {
            //Why are we cheacking for null features, CPQ can have child products even without features right?

            //If Bundle products in CPQ, create new eauivalent products in RCA
            if ((cpqProduct.SBQQ__Options__r != null && !cpqProduct.SBQQ__Options__r.isEmpty()) || (cpqProduct.SBQQ__Features__r != null && !cpqProduct.SBQQ__Features__r.isEmpty())) {
                Product2 newProduct = new Product2();
                newProduct.Name = cpqProduct.Name;
                newProduct.ProductCode = cpqProduct.ProductCode;
                newProduct.IsActive = cpqProduct.IsActive;
                newProduct.ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c;
                newProduct.Type = 'Bundle';
                if (String.isBlank(cpqProduct.StockKeepingUnit)) {
                    String firstThree = cpqProduct.Name.substring(0, 3).toUpperCase();
                    newProduct.StockKeepingUnit = firstThree + 'Bundle';
                } else {
                    newProduct.StockKeepingUnit = cpqProduct.StockKeepingUnit + 'Bundle';
                }
                newProduct.RecordTypeId = commercialRecordTypeId;
                newProductList.add(newProduct);
            } else {
                //update existing products with RCA equivalent data for standalone products - 
                cpqProduct.ConfigureDuringSale = cpqProduct.SBQQ__ConfigurationType__c;
                cpqProduct.IsSoldOnlyWithOtherProds = cpqProduct.SBQQ__Component__c;
                updateProductList.add(cpqProduct);
            }
        }

        if (!newProductList.isEmpty()) {
            insert newProductList;
        }
        if (!updateProductList.isEmpty()) {
            update updateProductList;
        }

        // Assign new products to catalogs - 
        List<ProductCategoryProduct> productCategoryProductList = new List<ProductCategoryProduct>();
        for (Product2 product : newProductList) {
            //Is only sold with other will always be false as per above logic while creating new Products?
            if (product.IsSoldOnlyWithOtherProds == false) {
                ProductCategoryProduct productCat = new ProductCategoryProduct();
                productCat.ProductId = product.Id;
                productCat.ProductCategoryId = category[0].Id;
                productCategoryProductList.add(productCat);
            }
        }

        // Assign old products to catalogs - 
        for (Product2 product : updateProductList) {
            if (product.IsSoldOnlyWithOtherProds == false) {
                ProductCategoryProduct productCat = new ProductCategoryProduct();
                productCat.ProductId = product.Id;
                productCat.ProductCategoryId = category[0].Id;
                productCategoryProductList.add(productCat);
            }
        }

        if (!productCategoryProductList.isEmpty()) {
            insert productCategoryProductList;
        }

        //Create productComponentGroup in RCA with equivalent data to Features in CPQ - 
        List<ProductComponentGroup> newComponentGroups = new List<ProductComponentGroup>();
        
        for (Product2 products : newProductList) {
            String pname = products.Name;
            List<SBQQ__ProductFeature__c> featureList = [
                SELECT Name, SBQQ__ConfiguredSKU__r.Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, SBQQ__Number__c
                FROM SBQQ__ProductFeature__c WHERE SBQQ__ConfiguredSKU__r.Name = :pname
            ];
            for (SBQQ__ProductFeature__c features : featureList) {
                ProductComponentGroup productCG = new ProductComponentGroup();
                productCG.Name = features.Name;
                productCG.MinBundleComponents = (Integer)features.SBQQ__MinOptionCount__c;
                productCG.MaxBundleComponents = (Integer)features.SBQQ__MaxOptionCount__c;
                productCG.Sequence = (Integer)features.SBQQ__Number__c;
                productCG.ParentProductId = products.Id;
                newComponentGroups.add(productCG);
            }
        }

        if (!newComponentGroups.isEmpty()) {
            insert newComponentGroups;
        }

        
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed.');
    }
}