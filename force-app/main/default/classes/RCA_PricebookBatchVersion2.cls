global class RCA_PricebookBatchVersion2 implements Database.Batchable<SObject>, Database.Stateful {

    private List<Id> productIds;
    private RCA_PricebookHelper helper = new RCA_PricebookHelper();

    
    global RCA_PricebookBatchVersion2() {}

    global RCA_PricebookBatchVersion2(List<Id> productIds) {
        this.productIds = productIds;
    }


    global Database.QueryLocator start(Database.BatchableContext bc) {

        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type FROM Product2';
        
        if (productIds != null && !productIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' WHERE Id IN :productIds');
        } else {
            return Database.getQueryLocator(baseQuery);
        }
    }

    global void execute(Database.BatchableContext BC, List<Product2> scope) {
        try {

            // RCA_PricebookHelper helper = new RCA_PricebookHelper();
            helper.processProducts(scope);
        } catch (Exception e) {
            // Catch unexpected errors and log them
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PricebookBatchVersion2',
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
        RCA_BatchExceptionLogger.flushLogs();
    }
    
}
