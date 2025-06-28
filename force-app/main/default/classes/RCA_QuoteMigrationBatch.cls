global class RCA_QuoteMigrationBatch implements Database.Batchable<SObject>{
    global Database.QueryLocator start(Database.BatchableContext bc){
        return Database.getQueryLocator([SELECT Id,Name, SBQQ__Account__c, SBQQ__Status__c, SBQQ__PrimaryContact__c,
                SBQQ__BillingName__c, SBQQ__ShippingName__c, SBQQ__ExpirationDate__c,
                SBQQ__LineItemCount__c, SBQQ__MasterContract__c, SBQQ__Partner__c,
                SBQQ__StartDate__c, SBQQ__Opportunity2__c
                FROM SBQQ__Quote__c where 	Is_Migrated__c = false]);
    }
    global void execute(Database.BatchableContext bc,List<SBQQ__Quote__c> scope){
        RCA_QuoteMigrationHelper.processQuotes(scope);
    }
    global void finish(Database.BatchableContext bc){
        System.debug('Batch is Completed Succesfully');
    }

}