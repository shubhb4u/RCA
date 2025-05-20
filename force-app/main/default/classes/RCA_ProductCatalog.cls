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
                for (Integer i = 0; i < insertResults.size(); i++) {
                    if (!insertResults[i].isSuccess()) {
                        Product2 failedProduct = newProducts[i];
                        String errorMsg = String.format(
                            'Product insert failed:\n' +
                            '  Name: {0}\n' +
                            '  ProductCode: {1}\n' +
                            '  SKU: {2}\n' +
                            '  Error: {3}\n' +
                            '  Fields: {4}',
                            new String[]{
                                failedProduct.Name,
                                failedProduct.ProductCode,
                                failedProduct.StockKeepingUnit,
                                insertResults[i].getErrors()[0].getMessage(),
                                String.join(insertResults[i].getErrors()[0].getFields(), ', ')
                            }
                        );
                        errorMessages.add(errorMsg);
                    }
                }
            }
            
            //4. Update existing products -
            if (!updatedProducts.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(updatedProducts, false);
                for (Integer i = 0; i < updateResults.size(); i++) {
                    if (!updateResults[i].isSuccess()) {
                        Product2 failedProduct = updatedProducts[i];
                        String errorMsg = String.format(
                            'Product update failed:\n' +
                            '  ID: {0}\n' +
                            '  Name: {1}\n' +
                            '  ProductCode: {2}\n' +
                            '  Error: {3}\n' +
                            '  Fields: {4}',
                            new String[]{
                                failedProduct.Id,
                                failedProduct.Name,
                                failedProduct.ProductCode,
                                updateResults[i].getErrors()[0].getMessage(),
                                String.join(updateResults[i].getErrors()[0].getFields(), ', ')
                            }
                        );
                        errorMessages.add(errorMsg);
                    }
                }
            }


            //5. Assign categories
            List<ProductCategoryProduct> categoryList = RCA_ProductCatalogHelper.assignCategory(origToNew.values(), defaultCategoryId);
            if (!categoryList.isEmpty()) {
                Database.SaveResult[] categoryResults = Database.insert(categoryList, false);
                for (Integer i = 0; i < categoryResults.size(); i++) {
                    if (!categoryResults[i].isSuccess()) {
                        ProductCategoryProduct failedAssignment = categoryList[i];
                        String errorMsg = String.format(
                            'Category assignment failed:\n' +
                            '  Product ID: {0}\n' +
                            '  Category ID: {1}\n' +
                            '  Error: {2}\n' +
                            '  Fields: {3}',
                            new String[] {
                                failedAssignment.ProductId,
                                failedAssignment.ProductCategoryId,
                                categoryResults[i].getErrors()[0].getMessage(),
                                String.join(categoryResults[i].getErrors()[0].getFields(), ', ')
                            }
                        );
                        errorMessages.add(errorMsg);
                    }
                }
            }
            
            //6. Create new ProductComponentGroups for new Products (Product Features)
            List<ProductComponentGroup> groups = RCA_ProductCatalogHelper.buildComponentGroups(origToNew, featureMap);
            if (!groups.isEmpty()) {
                Database.SaveResult[] groupResults = Database.insert(groups, false);
                for (Integer i = 0; i < groupResults.size(); i++) {
                    if (!groupResults[i].isSuccess()) {
                        ProductComponentGroup failedGroup = groups[i];
                        String errorMsg = String.format(
                            'Component Group insert failed:\n' +
                            '  Parent Product ID: {0}\n' +
                            '  Name: {1}\n' +
                            '  Min Components: {2}\n' +
                            '  Max Components: {3}\n' +
                            '  Sequence: {4}\n' +
                            '  Error: {5}\n' +
                            '  Fields: {6}',
                            new String[]{
                                failedGroup.ParentProductId,
                                failedGroup.Name,
                                String.valueOf(failedGroup.MinBundleComponents),
                                String.valueOf(failedGroup.MaxBundleComponents),
                                String.valueOf(failedGroup.Sequence),
                                groupResults[i].getErrors()[0].getMessage(),
                                String.join(groupResults[i].getErrors()[0].getFields(), ', ')
                            }
                        );
                        errorMessages.add(errorMsg);
                    }
                }
            }

            //6. Create new ProductRelatedComponent for new Products (Product Options)
            List<ProductRelatedComponent> relatedComponents = RCA_ProductCatalogHelper.buildRelatedComponents(origToNew, optionMap, groups, relationshipTypeId);
            if (!relatedComponents.isEmpty()) {
                Database.SaveResult[] relCompResults = Database.insert(relatedComponents, false);
                for (Integer i = 0; i < relCompResults.size(); i++) {
                    if (!relCompResults[i].isSuccess()) {
                        ProductRelatedComponent relComp = relatedComponents[i];
                        String errorMsg = String.format(
                            'Related Component insert failed:\n' +
                            '  Parent Product ID: {0}\n' +
                            '  Child Product ID: {1}\n' +
                            '  Group ID: {2}\n' +
                            '  Relationship Type ID: {3}\n' +
                            '  Error: {4}\n' +
                            '  Fields: {5}',
                            new String[]{
                                relComp.ParentProductId,
                                relComp.ChildProductId,
                                relComp.ProductComponentGroupId,
                                relComp.ProductRelationshipTypeId,
                                relCompResults[i].getErrors()[0].getMessage(),
                                String.join(relCompResults[i].getErrors()[0].getFields(), ', ')
                            }
                        );
                        errorMessages.add(errorMsg);
                    }
                }
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
        for (Integer i = 0; i < updateResults.size(); i++) {
            if (!updateResults[i].isSuccess()) {
                Product2 failedProduct = toUpdate[i];
                String errorMsg = String.format(
                    'Mark processed failed:\n' +
                    '  Product ID: {0}\n' +
                    '  Name: {1}\n' +
                    '  ProductCode: {2}\n' +
                    '  IsProcessed: {3}\n' +
                    '  Error: {4}\n' +
                    '  Fields: {5}',
                    new String[]{
                        failedProduct.Id,
                        failedProduct.Name,
                        failedProduct.ProductCode,
                        String.valueOf(failedProduct.IsProcessed__c),
                        updateResults[i].getErrors()[0].getMessage(),
                        String.join(updateResults[i].getErrors()[0].getFields(), ', ')
                    }
                );
                errorMessages.add(errorMsg);
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


