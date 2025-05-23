global class RCA_ProductCatalog implements Database.Batchable<SObject>, Database.Stateful {
    
    private List<String> errorMessages = new List<String>();
    private Id defaultCategoryId;
    private Id relationshipTypeId;
    private List<Id> productIds;

    global RCA_ProductCatalog() {}

    //Parameterized Constructor to execute batch explicitly as required - 
    global RCA_ProductCatalog(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {

        //Base query to retrieve all the CPQ Product records - 
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

    global void execute(Database.BatchableContext bc, List<Product2> CPQProductsList) {

            
            List<Product2> newProducts = new List<Product2>(); 
            List<Product2> updatedProducts = new List<Product2>(); 
            //To store original CPQ Bundle product Ids and new RCA Bundle products created - 
            Map<Id, Product2> origCPQToNewBundle = new Map<Id, Product2>(); 

            //1. Initialize default categories and default relationship type -
            initializeConfigIds();

            //2. Prepare map of CPQ products with their Features and Options to be used later -
            Map<Id, List<SBQQ__ProductFeature__c>> featureMap = RCA_ProductCatalogHelper.fetchFeatures(CPQProductsList);
            Map<Id, List<SBQQ__ProductOption__c>> optionMap = RCA_ProductCatalogHelper.fetchOptions(CPQProductsList);
            
            //4. Create newProducts, updatedProducts and create a Map <CPQProduct Id, New Bundles> -
            RCA_ProductCatalogHelper.buildProducts(CPQProductsList, featureMap, optionMap, newProducts, updatedProducts, origCPQToNewBundle);

            //5. Insert new bundle products
            if (!newProducts.isEmpty()) {

                try {
                    insert newProducts;
                } catch (DmlException ex) {

                    //Log only the records that failed - 
                    for (Integer i = 0; i < e.getNumDml(); i++) {
                        RCA_BatchExceptionLogger.logException(
                            'RCA_ProductCatalog','Insert Product failed', 
                            newProducts[i].StockKeepingUnit, ex
                        );
                    }
                }
            }

            //5. Insert new bundle products
            if (!updatedProducts.isEmpty()) {

                try {
                    update updatedProducts;
                } catch (DmlException ex) {
                    //Log only the records that failed - 
                    for (Integer i = 0; i < e.getNumDml(); i++) {
                        RCA_BatchExceptionLogger.logException(
                            'RCA_ProductCatalog','Update Product failed', 
                            updatedProducts[i].StockKeepingUnit, ex
                        );
                    }
                }
            }

            //.6 Insert new bundles - 
            if (!updatedProducts.isEmpty()) {
                try {
                    update updatedProducts;
                } catch (DmlException e) {
                    for (Integer i = 0; i < updatedProducts.size(); i++) {
                        RCA_BatchExceptionLogger.logException(
                            'RCA_ProductCatalog', 'Update Product', 
                            updatedProducts[i].StockKeepingUnit, e
                        );
                    }
                }
            }
            

            //5. Assign categories to both old CPQ records as well as new RCA products
            List<ProductCategoryProduct> categoryList = RCA_ProductCatalogHelper.assignCategory(origCPQToNewBundle.values(), defaultCategoryId);
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
            List<ProductComponentGroup> groups = RCA_ProductCatalogHelper.buildComponentGroups(origCPQToNewBundle, featureMap);
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
            List<ProductRelatedComponent> relatedComponents = RCA_ProductCatalogHelper.buildRelatedComponents(origCPQToNewBundle, optionMap, groups, relationshipTypeId);
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
            markProductsProcessed(CPQProductsList);

    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorNotification();
        }
    }

    private void initializeConfigIds() {
        
        if (defaultCategoryId == null) defaultCategoryId = RCA_ProductCatalogHelper.getCategoryId();
        if (relationshipTypeId == null) relationshipTypeId = RCA_ProductCatalogHelper.getRelationshipTypeId();
    }
 

    //Set IsProcessed__c to true once the products are processed - 
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

    //Create a meesage to include failed records details to be sent in an email 
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


