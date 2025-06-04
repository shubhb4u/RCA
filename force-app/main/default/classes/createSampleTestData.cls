public with sharing class createSampleTestData {
    public createSampleTestData() {

        List<Product2> productList = new List<Product2>();

        for (Integer i = 1; i <= 200; i++) {
            String paddedIndex = String.valueOf(i).leftPad(3, '0');
            String sku = 'Test' + paddedIndex + '_Bundle_SKU';

            Product2 p = new Product2(
                Name = 'Test Product ' + paddedIndex,
                ProductCode = sku,
                StockKeepingUnit = sku,
                IsActive = true,
                SBQQ__ConfigurationType__c = 'Allowed'
            );

            productList.add(p);
        }

        insert productList;
        System.debug('Inserted ' + productList.size() + ' Product2 records.');


        List<SBQQ__ProductFeature__c> featureList = new List<SBQQ__ProductFeature__c>();

        // Query the recently inserted 200 products by SKU prefix
        List<Product2> products = [
            SELECT Id, StockKeepingUnit 
            FROM Product2 
            WHERE StockKeepingUnit LIKE 'Test%_Bundle_SKU'
            LIMIT 200
        ];

        for (Product2 prod : products) {
            // Generate 1 or 2 features randomly
            Integer featureCount = Math.mod(Crypto.getRandomInteger(), 2) == 0 ? 1 : 2;

            for (Integer j = 1; j <= featureCount; j++) {
                SBQQ__ProductFeature__c feature = new SBQQ__ProductFeature__c(
                    Name = prod.StockKeepingUnit + '_Feature_' + j,
                    SBQQ__MinOptionCount__c = 0,
                    SBQQ__MaxOptionCount__c = 5,
                    SBQQ__Number__c = j,
                    SBQQ__ConfiguredSKU__c = prod.Id
                );
                featureList.add(feature);
            }
        }

        insert featureList;
        System.debug('Inserted ' + featureList.size() + ' SBQQ__ProductFeature__c records.');

        // Fetch existing bundle products and features
        List<Product2> bundleProducts = [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit LIKE 'Test%_SKU'];
        List<SBQQ__ProductFeature__c> features = [SELECT Id, SBQQ__ConfiguredSKU__c FROM SBQQ__ProductFeature__c];
        List<Product2> standaloneProds = [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit LIKE 'STANDALONE_%'];

        List<SBQQ__ProductOption__c> options = new List<SBQQ__ProductOption__c>();

        Integer optionIndex = 1;

        for (Product2 bundle : bundleProducts) {
            Integer featureCount = 0;

            for (SBQQ__ProductFeature__c feature : features) {
                if (feature.SBQQ__ConfiguredSKU__c == bundle.StockKeepingUnit && featureCount < 1) {
                    // Create an option with feature + bundle
                    Product2 randomStandalone = standaloneProds[Math.mod(Crypto.getRandomInteger(), standaloneProds.size())];

                    SBQQ__ProductOption__c optionWithFeature = new SBQQ__ProductOption__c(
                        Name = 'Option_WithFeature_' + optionIndex++,
                        SBQQ__ConfiguredSKU__c = bundle.StockKeepingUnit,
                        SBQQ__Feature__c = feature.Id,
                        SBQQ__OptionalSKU__c = randomStandalone.StockKeepingUnit
                    );
                    options.add(optionWithFeature);
                    featureCount++;
                }
            }

            // Also add an option without feature
            Product2 randomStandalone = standaloneProds[Math.mod(Crypto.getRandomInteger(), standaloneProds.size())];

            SBQQ__ProductOption__c optionWithoutFeature = new SBQQ__ProductOption__c(
                Name = 'Option_NoFeature_' + optionIndex++,
                SBQQ__ConfiguredSKU__c = bundle.StockKeepingUnit,
                SBQQ__OptionalSKU__c = randomStandalone.StockKeepingUnit
            );
            options.add(optionWithoutFeature);
        }

        insert options;
        System.debug('Inserted Options: ' + options.size());

    }

}