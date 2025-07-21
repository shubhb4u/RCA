global class RCA_Pricebook implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private RCA_PricebookHelper helper = new RCA_PricebookHelper();

    global RCA_Pricebook() {}

    global RCA_Pricebook(List<Id> productIds) {
        this.productIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {

        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c, SBQQ__SubscriptionTerm__c, IsProcessed__c FROM Product2 Where IsProcessed__c =  false' +
        ' AND SBQQ__PricingMethod__c = \'List\'';
                
        if (productIds != null && !productIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' AND Id IN :productIds');
        } else {
            return Database.getQueryLocator(baseQuery);
        }
    }

    global void execute(Database.BatchableContext BC, List<Product2> scope) {
        try {

            helper.processProducts(scope);
        } catch (Exception e) {
            // Catch unexpected errors and log them
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_Pricebook',
                'execute',
                'Product2',
                null,
                'Unhandled exception: ' + e.getMessage()
            );
        } finally {
            // Make sure to flush logs for this batch chunk
            RCA_BatchExceptionLogger.flushLogs();
        }
    }
    
    global void finish(Database.BatchableContext bc) {
    }
}