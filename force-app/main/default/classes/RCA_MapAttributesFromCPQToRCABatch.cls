global class RCA_MapAttributesFromCPQToRCABatch implements Database.Batchable<SObject>, Database.Stateful {

    public List<Id> inputProductIds;

    // Shared error list to collect errors from helper
    public List<String> errorMessages = new List<String>();

    // Default constructor: processes all products with config attributes and no BasedOnId
    public RCA_MapAttributesFromCPQToRCABatch() {}

    // Overloaded constructor: accepts specific product IDs to process
    public RCA_MapAttributesFromCPQToRCABatch(List<Id> productIds) {
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

    global void execute(Database.BatchableContext bc, List<Product2> scope) {
        // Pass the shared error list to the helper
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper(errorMessages);

        try {
            helper.process(scope);
        } catch (Exception e) {
            errorMessages.add('Batch execution error: ' + e.getMessage());
        }
    }

    global void finish(Database.BatchableContext bc) {
        if (!errorMessages.isEmpty()) {
            sendErrorEmail(errorMessages);
        }
    }

    private void sendErrorEmail(List<String> errors) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{'Shubham.m@etg.digital'}); // Replace with actual email
        mail.setSubject('RCA Map Attributes Batch - Errors Report');
        mail.setPlainTextBody('The following errors occurred during batch processing:\n\n' + String.join(errors, '\n'));
        try {
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        } catch (Exception e) {
            System.debug('Error sending batch error email: ' + e.getMessage());
        }
    }
}
