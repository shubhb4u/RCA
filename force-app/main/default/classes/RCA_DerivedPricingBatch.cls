global class RCA_DerivedPricingBatch implements Database.Batchable<SObject>, Database.Stateful {

    private RCA_DerivedPricingHelper helper;
    private List<Id> productIds;

    public RCA_DerivedPricingBatch() {
        this.helper = new RCA_DerivedPricingHelper();
    }

    public RCA_DerivedPricingBatch(List<Id> productIds) {
        this.productIds = productIds;
        this.helper = new RCA_DerivedPricingHelper();
    }

    global Database.QueryLocator start(Database.BatchableContext BC) {
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, SBQQ__SubscriptionPercent__c, SBQQ__SubscriptionBase__c, SBQQ__SubscriptionTarget__c ' +
                           'FROM Product2 WHERE SBQQ__PricingMethod__c = \'Percent Of Total\'';

        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' AND Id IN :productIds';
        }

        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext BC, List<SObject> potProducts) {
        helper.processProducts((List<Product2>) potProducts);
    }

    global void finish(Database.BatchableContext BC) {
        

    }
}
