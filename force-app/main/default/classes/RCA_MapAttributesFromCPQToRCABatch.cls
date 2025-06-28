global class RCA_MapAttributesFromCPQToRCABatch implements Database.Batchable<SObject>, Database.Stateful {

    public List<Id> inputProductIds;

    global RCA_MapAttributesFromCPQToRCABatch() {}
    global RCA_MapAttributesFromCPQToRCABatch(List<Id> productIds) {
        this.inputProductIds = productIds;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery = 'SELECT Id, Name, SBQQ__HasConfigurationAttributes__c, BasedOnId, StockKeepingUnit FROM Product2 WHERE SBQQ__HasConfigurationAttributes__c = true AND (BasedOnId = null OR BasedOnId = \'\')';
        if (inputProductIds != null && !inputProductIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' AND Id IN :inputProductIds');
        } else {
            return Database.getQueryLocator(baseQuery);
        }
    }

    global void execute(Database.BatchableContext bc, List<Product2> productList) {
        try {
            RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper();
            helper.process(productList);
        } catch (Exception e) {
            RCA_BatchExceptionLogger.logException(
                'RCA_MapAttributesFromCPQToRCABatch',
                'execute',
                'Product2',
                null,
                productList != null && !productList.isEmpty() ? String.valueOf(productList[0].Id) : 'N/A'
            );
        }
    }

    global void finish(Database.BatchableContext bc) {
        // No email notifications, since error logging is handled per-error
    }
}