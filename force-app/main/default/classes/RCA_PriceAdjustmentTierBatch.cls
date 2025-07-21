global class RCA_PriceAdjustmentTierBatch implements Database.Batchable<SObject>, Database.Stateful {
    global Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Name, SBQQ__Type__c, SBQQ__DiscountUnit__c, SBQQ__Product__c, SBQQ__Pricebook__c, IsMigrated__c
            FROM SBQQ__DiscountSchedule__c
            WHERE IsMigrated__c = false
        ]);
    }
    global void execute(Database.BatchableContext context, List<SBQQ__DiscountSchedule__c> scope) {
        try {
            RCA_PriceAdjustmentTierHelper.ProcessPriceAdjustmentSchedule(scope);
        } catch (Exception e) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PriceAdjustmentTierBatch',
                'Error in execute method',
                'SBQQ__DiscountSchedule__c',
                null,
                'Failed to process Discount Schedules in batch. Error: ' + e.getMessage()
            );
        }
    }
    global void finish(Database.BatchableContext context) {
        // No email notifications, since error logging is handled per-error    }
        RCA_BatchExceptionLogger.flushLogs();

    }
}