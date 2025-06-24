public class RCA_QuoteMigrationHelper {

    public static Set<String> getExistingRcaQuoteNames() {
        Set<String> names = new Set<String>();
        //new Quote name is in the format of 'RCA - oldCPQuote Name'(old cpq quote name is autonumber so no pre-existing quotes wil be available)
        //collects all the existing quotes which are already migrated
        for (Quote q : [SELECT Name FROM Quote WHERE Name LIKE 'RCA - %']) { //>51000
            if (q.Name != null && q.Name.startsWith('RCA - ')) {
                names.add(q.Name.removeStart('RCA - '));
            }
        }
        return names;
    }

    //--------------------------- Added LIMIT 50000, can keep it smaller if possible -----------------------------------------

    // public static Set<String> getExistingRcaQuoteNames() {
    //     Set<String> names = new Set<String>();
    //     // Process in batches of 50,000
    //     for (Quote q : [SELECT Name FROM Quote 
    //                     WHERE Name LIKE 'RCA - %' 
    //                     LIMIT 50000]) {
    //         names.add(q.Name.removeStart('RCA - '));
    //     }
    //     return names;
    // }
    
    public static void migrateQuotes(List<SBQQ__Quote__c> oldQuotesList) {
        //custom metadata to associate the pricebook of RCA_Pricebook
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        String Rca_PriceBookId = config.RCA_PricebookId__c;
        List<Quote> newQuotes = new List<Quote>();
	// mapping all the related fields
        for (SBQQ__Quote__c oldQuote : oldQuotesList) {
            Quote q = new Quote();
            q.Name = 'RCA - ' + oldQuote.Name;
            q.QuoteAccountId = oldQuote.SBQQ__Account__c;
            q.Status = oldQuote.SBQQ__Status__c;
            q.ContactId = oldQuote.SBQQ__PrimaryContact__c;
            q.BillingName = oldQuote.SBQQ__BillingName__c;
            q.ShippingName = oldQuote.SBQQ__ShippingName__c;
            q.ExpirationDate = oldQuote.SBQQ__ExpirationDate__c;
            q.ContractId = oldQuote.SBQQ__MasterContract__c;
            q.PartnerAccountId = oldQuote.SBQQ__Partner__c;
            q.StartDate = oldQuote.SBQQ__StartDate__c;
            q.OpportunityId = oldQuote.SBQQ__Opportunity2__c;  // In this org it is not working properly may be due to deletion of opportunity which used in quotes.
            q.Pricebook2Id=Rca_PriceBookId;

            newQuotes.add(q);
        }

        if (!newQuotes.isEmpty()) {
            try {
                insert newQuotes;
            } catch (DmlException e) {
                System.debug('Error inserting quotes: ' + e.getMessage());
            }
        }
    }
}