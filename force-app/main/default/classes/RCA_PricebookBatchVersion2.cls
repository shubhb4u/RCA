global class RCA_PricebookBatchVersion2 implements Database.Batchable<SObject>, Database.Stateful {
    private List<Id> productIds;
    private List<String> errorMessages = new List<String>();
    private RCA_PricebookHelper helper = new RCA_PricebookHelper();

    global RCA_PricebookBatchVersion2(List<Id> productIds) {
        this.productIds = productIds;
    }

    global RCA_PricebookBatchVersion2() {}

    global Database.QueryLocator start(Database.BatchableContext bc) {
        System.debug('### Start method called');
        String baseQuery = 'SELECT Id, Name, StockKeepingUnit, Type FROM Product2';
        if (productIds != null && !productIds.isEmpty()) {
            System.debug('### Filtering products with provided productIds: ' + productIds);
            return Database.getQueryLocator(baseQuery + ' WHERE Id IN :productIds');
        } else {
            System.debug('### No productIds provided, querying all products');
            return Database.getQueryLocator(baseQuery);
        }
    }

    global void execute(Database.BatchableContext bc, List<Product2> products) {
        helper.processProducts(products);
        errorMessages.addAll(helper.errorMessages);
    }

    global void finish(Database.BatchableContext bc) {
        System.debug('### Finish method called');
        if (!errorMessages.isEmpty()) {
            System.debug('### Errors encountered: ' + errorMessages);
            sendErrorEmail();
        } else {
            System.debug('### RCA_PricebookBatchVersion2 completed successfully with no errors.');
        }
    }

    private void sendErrorEmail() {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[] { 'Shubham.m@etg.digital' });
        mail.setSubject('RCA_PricebookBatchVersion2 Errors');
        mail.setPlainTextBody('The batch encountered errors:\n\n' + String.join(errorMessages, '\n'));
        Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
        System.debug('### Sent error email with ' + errorMessages.size() + ' messages.');
    }
}