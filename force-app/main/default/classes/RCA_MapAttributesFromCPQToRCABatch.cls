public class RCA_MapAttributesFromCPQToRCABatch implements Database.Batchable<SObject> {

    private List<Id> inputProductIds;

    // Default constructor: processes all products with config attributes and no BasedOnId
    public RCA_MapAttributesFromCPQToRCABatch() {}

    // Overloaded constructor: accepts specific product IDs to process
    public RCA_MapAttributesFromCPQToRCABatch(List<Id> productIds) {
        this.inputProductIds = productIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String baseQuery = 'SELECT Id, Name, SBQQ__HasConfigurationAttributes__c, BasedOnId, StockKeepingUnit FROM Product2 WHERE SBQQ__HasConfigurationAttributes__c = true AND (BasedOnId = null OR BasedOnId = \'\')';

        if (inputProductIds != null && !inputProductIds.isEmpty()) {
            return Database.getQueryLocator(baseQuery + ' AND Id IN :inputProductIds');
        } else {
            return Database.getQueryLocator(baseQuery);
        }
    }

    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper();
        helper.process(scope);
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('Batch job completed.');
    }
}
