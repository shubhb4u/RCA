public class RCA_QuoteMigrationHelper {
    public static void processQuotes(List<SBQQ__Quote__c> oldQuotesList){
        try{
        List<Quote> newQuotesToInsert = new List<Quote>();
            List<SBQQ__Quote__c> oldQuotesToUpdate = new List<SBQQ__Quote__c>();
            for (SBQQ__Quote__c oldQuote : oldQuotesList) {
                Quote newQuote = new Quote();
                newQuote.Name = 'RCA - ' + oldQuote.Name;
                newQuote.QuoteAccountId = oldQuote.SBQQ__Account__c;
                newQuote.Status = oldQuote.SBQQ__Status__c;
                newQuote.OpportunityId = oldQuote.SBQQ__Opportunity2__c;
                newQuote.ContactId = oldQuote.SBQQ__PrimaryContact__c;
                newQuote.BillingName = oldQuote.SBQQ__BillingName__c;
                newQuote.ShippingName = oldQuote.SBQQ__ShippingName__c;
                newQuote.ExpirationDate = oldQuote.SBQQ__ExpirationDate__c;
                newQuote.ContractId = oldQuote.SBQQ__MasterContract__c;
                newQuote.PartnerAccountId = oldQuote.SBQQ__Partner__c;
                newQuote.StartDate = oldQuote.SBQQ__StartDate__c;
                
                newQuotesToInsert.add(newQuote);
                oldQuote.Is_Migrated__c=true;
                oldQuotesToUpdate.add(oldQuote);
            }
            if(!newQuotesToInsert.isEmpty()){
                insert newQuotesToInsert;
                update oldQuotesToUpdate;
            }
        }
        catch(Exception e){
            System.debug(e.getMessage());
        }
    }
}