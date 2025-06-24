global class RCA_QuoteMigrationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Stateful variables to track progress
    global Integer totalRecordsProcessed = 0;
    global Integer totalBatchesExecuted = 0;
    global Set<String> processedQuoteNames = new Set<String>();

    global Database.QueryLocator start(Database.BatchableContext bc) {
        Set<String> existingRcaQuoteNames = RCA_QuoteMigrationHelper.getExistingRcaQuoteNames();

	// selects the sbqq__quotes__c which are not migrated yet
        return Database.getQueryLocator([ 
            SELECT Name, SBQQ__Account__c, SBQQ__Status__c, SBQQ__PrimaryContact__c,
                   SBQQ__BillingName__c, SBQQ__ShippingName__c, SBQQ__ExpirationDate__c,
                   SBQQ__LineItemCount__c, SBQQ__MasterContract__c, SBQQ__Partner__c,
                   SBQQ__StartDate__c, SBQQ__Opportunity2__c
            FROM SBQQ__Quote__c
            WHERE Name NOT IN :existingRcaQuoteNames 
        ]);
    }

    global void execute(Database.BatchableContext bc, List<SBQQ__Quote__c> oldQuotesList) {
        RCA_QuoteMigrationHelper.migrateQuotes(oldQuotesList); //200

    }

    global void finish(Database.BatchableContext bc) {
        System.debug(' RCA Quote Migration batch completed.');

        
    }
}