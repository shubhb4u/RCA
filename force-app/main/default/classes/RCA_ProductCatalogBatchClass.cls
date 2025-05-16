global class RCA_ProductCatalogBatchClass implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();

    global RCA_ProductCatalogBatchClass() {}
    global RCA_ProductCatalogBatchClass(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {

        String baseQuery =
            'SELECT Id, Name, ProductCode, IsActive, SBQQ__ConfigurationType__c, ' +
            'SBQQ__Component__c, StockKeepingUnit, ' +
            '(SELECT Id, SBQQ__OptionalSKU__c, SBQQ__Number__c, SBQQ__Selected__c, ' +
            'SBQQ__Required__c, SBQQ__Quantity__c, SBQQ__Feature__c, SBQQ__Feature__r.Name, ' +
            'SBQQ__QuantityEditable__c, SBQQ__MinQuantity__c, SBQQ__MaxQuantity__c, ' +
            'SBQQ__Bundled__c FROM SBQQ__Options__r), ' +
            '(SELECT Id, Name, SBQQ__MinOptionCount__c, SBQQ__MaxOptionCount__c, ' +
            'SBQQ__Number__c FROM SBQQ__Features__r) ' +
            'FROM Product2 ' + 'WHERE IsProcessed__c = FALSE';

        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' AND Id IN :productIds';
        }
        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext bc, List<Product2> scope) {
        Id rtId      = RCA_ProductCatalogHelper.getRecordTypeId();
        Id relTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();

        Map<Id, List<SBQQ__ProductFeature__c>> featureMap = 
            RCA_ProductCatalogHelper.fetchFeatures(scope);
        Map<Id, List<SBQQ__ProductOption__c>> optionMap  = 
            RCA_ProductCatalogHelper.fetchOptions(scope);

        List<Product2> newProds = new List<Product2>();
        List<Product2> updProds = new List<Product2>();
        Map<Id, Product2> origToNew = RCA_ProductCatalogHelper.buildProducts(
            scope, featureMap, optionMap, newProds, updProds, rtId
        );

        // 1) create bundles
        insertNewProducts(newProds);

        // 2) flag originals as processed
        flagProcessed(origToNew.keySet());

        // 3) update original metadata (ConfigureDuringSale etc)
        updateOriginalProducts(updProds);

        // 4) assign default category
        Id catId = RCA_ProductCatalogHelper.getCategoryId();
        if (catId != null) {
            RCA_ProductCatalogHelper.assignCategory(
                RCA_ProductCatalogHelper.getAllIds(newProds, updProds),
                catId
            );
        }

        // 5) build & insert component groups
        List<ProductComponentGroup> groups = 
            RCA_ProductCatalogHelper.buildComponentGroups(origToNew, featureMap);
        insertGroups(groups);

        // 6) build & insert related components
        List<ProductRelatedComponent> rels = 
            RCA_ProductCatalogHelper.buildRelatedComponents(
                origToNew, optionMap, groups, relTypeId
            );
        insertRelatedComponents(rels);
    }

    private void insertNewProducts(List<Product2> records) {
        if (records.isEmpty()) return;
        List<Database.SaveResult> results = Database.insert(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'Insert NewProd['+i+'] Name:'+records[i].Name+
                        ' – '+err.getStatusCode()+': '+err.getMessage()
                    );
                }
            } else {
                // capture new Id for downstream grouping
                records[i].Id = results[i].getId();
            }
        }
    }

    private void flagProcessed(Set<Id> originalIds) {
        if (originalIds.isEmpty()) return;
        List<Product2> toFlag = new List<Product2>();
        for (Id origId : originalIds) {
            toFlag.add(new Product2(
                Id = origId,
                IsProcessed__c = true
            ));
        }
        List<Database.SaveResult> results = Database.update(toFlag, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'FlagProcessed['+i+'] OrigId:'+toFlag[i].Id+
                        ' – '+err.getStatusCode()+': '+err.getMessage()
                    );
                }
            }
        }
    }

    private void updateOriginalProducts(List<Product2> records) {
        if (records.isEmpty()) return;
        List<Database.SaveResult> results = Database.update(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'Update OrigProd['+i+'] Id:'+records[i].Id+
                        ' – '+err.getStatusCode()+': '+err.getMessage()
                    );
                }
            }
        }
    }

    private void insertGroups(List<ProductComponentGroup> records) {
        if (records.isEmpty()) return;
        List<Database.SaveResult> results = Database.insert(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'Insert Group['+i+'] Parent:'+records[i].ParentProductId+
                        ' – '+err.getStatusCode()+': '+err.getMessage()
                    );
                }
            } else {
                records[i].Id = results[i].getId();
            }
        }
    }

    private void insertRelatedComponents(List<ProductRelatedComponent> records) {
        if (records.isEmpty()) return;
        List<Database.SaveResult> results = Database.insert(records, false);
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                for (Database.Error err : results[i].getErrors()) {
                    errorMessages.add(
                        'Insert RelComp['+i+'] Parent:'+records[i].ParentProductId+
                        ' Child:'+records[i].ChildProductId+
                        ' – '+err.getStatusCode()+': '+err.getMessage()
                    );
                }
            }
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (errorMessages.isEmpty()) {
            System.debug('Batch completed with no errors.');
            return;
        }
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{'ops-team@example.com'});
        mail.setSubject('RCA ProdCatalog Batch Errors – ' + 
                        Datetime.now().format('yyyy-MM-dd HH:mm'));
        mail.setPlainTextBody(
            'Errors in RCA_ProductCatalogBatchClass:\n\n' +
            String.join(errorMessages, '\n')
        );
        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }
}