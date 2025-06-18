global class RCA_BundleDerivedPricingBatch implements Database.Batchable<SObject>, Database.Stateful {

    private RCA_BundleDerivedPricingBatchHelper helper;
    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();

    public RCA_BundleDerivedPricingBatch() {
        this.helper = new RCA_BundleDerivedPricingBatchHelper(errorMessages);
    }

    public RCA_BundleDerivedPricingBatch(List<Id> productIds) {
        this.productIds = productIds;
        this.helper = new RCA_BundleDerivedPricingBatchHelper(errorMessages);
    }

    global Database.QueryLocator start(Database.BatchableContext BC) {
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, SBQQ__SubscriptionPercent__c, SBQQ__SubscriptionBase__c, SBQQ__SubscriptionTarget__c ' +
                           'FROM Product2 WHERE Type = \'Bundle\'';

        if (productIds != null && !productIds.isEmpty()) {
            baseQuery += ' AND Id IN :productIds';
        }

        return Database.getQueryLocator(baseQuery);
    }

    global void execute(Database.BatchableContext BC, List<SObject> potBundleProducts) {
        
        System.debug('potBundleProducts in 2nd Helper class -->>>> ');
        helper.processProducts((List<Product2>) potBundleProducts);
    }

    global void finish(Database.BatchableContext BC) {
        
        if (!errorMessages.isEmpty()) {
            String subject = 'RCA Derived Pricing Batch Errors';
            String body = 'The following errors occurred during the RCA Derived Pricing Batch:\n\n' + String.join(errorMessages, '\n');

            // Send error email
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' }); // <-- Change to your recipient
            mail.setSubject(subject);
            mail.setPlainTextBody(body);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

            System.debug('Errors during Derived Pricing Batch:\n' + body);
        } else {
            System.debug('RCA Derived Pricing Batch completed without errors.');
        }
    }
}