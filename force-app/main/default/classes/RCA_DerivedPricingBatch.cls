global class RCA_DerivedPricingBatch implements Database.Batchable<SObject> {
    
    global Database.QueryLocator start(Database.BatchableContext bc) {
        // Dummy query — we don’t need actual records, just to kick off logic
        return Database.getQueryLocator([SELECT Id FROM Product2 LIMIT 1]);
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        RCA_DerivedPricingHelper.processDerivedPricing();
    }

    global void finish(Database.BatchableContext bc) {
        // Optionally add logic like logging or sending a confirmation email
    }
}