global class RCA_ProductCatalog implements Database.Batchable<SObject>, Database.Stateful {
    
    @TestVisible
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
            'SBQQ__Component__c, StockKeepingUnit, RecordTypeId, ' +
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
            List<Product2> newProducts = new List<Product2>();
            List<Product2> updatedProducts = new List<Product2>();

            //1. Initialize default catalog/ categories and default relationship type -
            initializeConfigIds();

            //2. Prepare mapping ofC CPQ products with their Features and Options to be used later -
            Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogHelper.fetchFeatures(scope);
            Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogHelper.fetchOptions(scope);

            Map<Id, Product2> origToNew = RCA_ProductCatalogHelper.buildProducts(scope, featureMap, optionMap, newProducts, updatedProducts);
            
            //.3 Insert new bundles - 
            if (!newProducts.isEmpty()) {
                Database.SaveResult[] insertResults = Database.insert(newProducts, false);
                handleDmlErrors(
                    newProducts,
                    insertResults,
                    'Product insert failed',
                    new List<String>{'Name', 'ProductCode', 'StockKeepingUnit'}
                );
            }
            
            //4. Update existing products -
            if (!updatedProducts.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(updatedProducts, false);
                handleDmlErrors(
                    updatedProducts,
                    updateResults,
                    'Product update failed',
                    new List<String>{'Id', 'Name', 'ProductCode'}
                );
            }


            //5. Assign categories
            List<ProductCategoryProduct> categoryList = RCA_ProductCatalogHelper.assignCategory(origToNew.values(), defaultCategoryId);
            if (!categoryList.isEmpty()) {
                Database.SaveResult[] categoryResults = Database.insert(categoryList, false);
                handleDmlErrors(
                    categoryList,
                    categoryResults,
                    'Category assignment failed',
                    new List<String>{'ProductId', 'ProductCategoryId'}
                );
            }
            
            //6. Create new ProductComponentGroups for new Products (Product Features)
            List<ProductComponentGroup> groups = RCA_ProductCatalogHelper.buildComponentGroups(origToNew, featureMap);
            if (!groups.isEmpty()) {
                Database.SaveResult[] groupResults = Database.insert(groups, false);
                handleDmlErrors(
                    groups,
                    groupResults,
                    'Component Group insert failed',
                    new List<String>{'ParentProductId', 'Name', 'MinBundleComponents', 'MaxBundleComponents', 'Sequence'}
                );
            }

            //6. Create new ProductRelatedComponent for new Products (Product Options)
            List<ProductRelatedComponent> relatedComponents = RCA_ProductCatalogHelper.buildRelatedComponents(origToNew, optionMap, groups, relationshipTypeId);
            if (!relatedComponents.isEmpty()) {
                Database.SaveResult[] relCompResults = Database.insert(relatedComponents, false);
                handleDmlErrors(
                    relatedComponents,
                    relCompResults,
                    'Related Component insert failed',
                    new List<String>{'ParentProductId', 'ChildProductId', 'ProductComponentGroupId', 'ProductRelationshipTypeId'}
                );
            }
            
            //7. Update processed CPQ records as true - 
            markProductsProcessed(scope);

        } catch (Exception ex) {
            errorMessages.add('Batch execution error: ' + ex.getMessage() + 
                        '\nStack Trace: ' + ex.getStackTraceString());
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    // Helper methods
    private void initializeConfigIds() {
        
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();
    }
 

    private void markProductsProcessed(List<Product2> processedProducts) {
        List<Product2> toUpdate = new List<Product2>();
        for (Product2 p : processedProducts) {
            p.IsProcessed__c = true;
            toUpdate.add(p);
        }
        
        Database.SaveResult[] updateResults = Database.update(toUpdate, false);
        handleDmlErrors(
            toUpdate,
            updateResults,
            'Mark processed failed',
            new List<String>{'Id', 'Name', 'ProductCode', 'IsProcessed__c'}
        );
    }

    private void handleDmlErrors(List<SObject> records, Database.SaveResult[] results, String context, List<String> fieldNames) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                SObject failedRecord = records[i];
                Database.Error error = results[i].getErrors()[0];
                
                errorMessages.add(RCA_ProductCatalogHelper.formatDmlError(
                    context,
                    failedRecord,
                    error,
                    fieldNames
                ));
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


