global class RCA_DerivedPricingBatch implements Database.Batchable<SObject>, Database.Stateful {

    private RCA_DerivedPricingHelper helper = new RCA_DerivedPricingHelper();

    global Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, Name, StockKeepingUnit, SBQQ__SubscriptionPercent__c, SBQQ__SubscriptionBase__c
            FROM Product2
            WHERE SBQQ__PricingMethod__c = 'Percent Of Total' AND SBQQ__SubscriptionBase__c = 'Net'
        ]);
    }

    global void execute(Database.BatchableContext BC, List<SObject> scope) {
        List<Product2> potProducts = (List<Product2>) scope;

        helper.collectPOTData(potProducts);
        helper.deleteOldPBEs();
        helper.insertNewPBEs();
        helper.createDerivedPricesForNewPBEs();
        helper.prepareAndInsertBundlePBEs();
        helper.createDerivedPricesForBundles();
    }

    global void finish(Database.BatchableContext BC) {
        helper.insertDerivedPrices();
    }
}