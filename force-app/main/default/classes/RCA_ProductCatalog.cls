global class RCA_ProductCatalog implements Database.Batchable<SObject>, Database.Stateful {
    
    private List<String> errorMessages = new List<String>();
    private Id defaultCategoryId;
    private Id recordTypeId;
    private Id relationshipTypeId;
    private List<Id> productIds;

    global RCA_ProductCatalog() {}
    global RCA_ProductCatalog(List<Id> productIds) {
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

        try {
            initializeConfigIds();

            Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogHelper.fetchFeatures(scope);
            Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogHelper.fetchOptions(scope);

            List<Product2> newProducts = new List<Product2>();
            List<Product2> updatedProducts = new List<Product2>();

            Map<Id, Product2> origToNew = buildBundlesAndProducts(scope, featureMap, optionMap, newProducts, updatedProducts);

            if (!newProducts.isEmpty()) {
                Database.SaveResult[] insertResults = Database.insert(newProducts, false);
                for (Integer i = 0; i < insertResults.size(); i++) {
                    if (!insertResults[i].isSuccess()) {
                        errorMessages.add('Insert failed for Product: ' + newProducts[i].Name +
                                          ' - ' + insertResults[i].getErrors()[0].getMessage());
                    }
                }
            }
            
            if (!updatedProducts.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(updatedProducts, false);
                for (Integer i = 0; i < updateResults.size(); i++) {
                    if (!updateResults[i].isSuccess()) {
                        errorMessages.add('Update failed for Product: ' + updatedProducts[i].Name +
                                          ' - ' + updateResults[i].getErrors()[0].getMessage());
                    }
                }
            }
            

            assignDefaultCategory(origToNew.values());

            List<ProductComponentGroup> groups = buildComponentGroups(origToNew, featureMap);
            if (!groups.isEmpty()) {
                Database.SaveResult[] groupResults = Database.insert(groups, false);
                for (Integer i = 0; i < groupResults.size(); i++) {
                    if (!groupResults[i].isSuccess()) {
                        errorMessages.add('Insert failed for Component Group: ' + groups[i].Name +
                                          ' - ' + groupResults[i].getErrors()[0].getMessage());
                    }
                }
            }

            List<ProductRelatedComponent> relatedComponents = buildRelatedComponents(origToNew, optionMap, groups);
            if (!relatedComponents.isEmpty()) {
                Database.SaveResult[] relCompResults = Database.insert(relatedComponents, false);
                for (Integer i = 0; i < relCompResults.size(); i++) {
                    if (!relCompResults[i].isSuccess()) {
                        errorMessages.add('Insert failed for Related Component - ' +
                                          relCompResults[i].getErrors()[0].getMessage());
                    }
                }
            }

            markProductsProcessed(scope);

        } catch (Exception ex) {
            errorMessages.add('Batch execution error: ' + ex.getMessage());
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    // Helper methods
    private void initializeConfigIds() {
        if (recordTypeId == null) recordTypeId = RCA_ProductCatalogHelper.getRecordTypeId();
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();
    }

    private Map<Id, Product2> buildBundlesAndProducts(
        List<Product2> scope,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<Product2> newProducts,
        List<Product2> updatedProducts
    ) {
        return RCA_ProductCatalogHelper.buildProducts(scope, featureMap, optionMap, newProducts, updatedProducts, recordTypeId);
    }

    private void assignDefaultCategory(Iterable<Product2> products) {
        Set<Id> productIds = new Set<Id>();
        for (Product2 p : products) {
            if (p.Id != null) productIds.add(p.Id);
        }
        RCA_ProductCatalogHelper.assignCategory(productIds, defaultCategoryId);
    }

    private List<ProductComponentGroup> buildComponentGroups(
        Map<Id, Product2> origToNew,
        Map<Id, List<SBQQ__ProductFeature__c>> featureMap
    ) {
        return RCA_ProductCatalogHelper.buildComponentGroups(origToNew, featureMap);
    }

    private List<ProductRelatedComponent> buildRelatedComponents(
        Map<Id, Product2> origToNew,
        Map<Id, List<SBQQ__ProductOption__c>> optionMap,
        List<ProductComponentGroup> groups
    ) {
        return RCA_ProductCatalogHelper.buildRelatedComponents(origToNew, optionMap, groups, relationshipTypeId);
    }

    private void markProductsProcessed(List<Product2> processedProducts) {
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
        }
        Database.SaveResult[] updateResults = Database.update(processedProducts, false);
        for (Integer i = 0; i < updateResults.size(); i++) {
            if (!updateResults[i].isSuccess()) {
                errorMessages.add('Marking as processed failed for: ' + processedProducts[i].Name +
                                ' - ' + updateResults[i].getErrors()[0].getMessage());
            }
        }

    }

    private void sendErrorNotification() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA Product Catalog Batch Process Errors');
        mail.setPlainTextBody('Errors during batch execution:\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
    }
}
