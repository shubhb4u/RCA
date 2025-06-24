public class RCA_QuoteLines {
    public void quotelinemigration(){
        
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        String Rca_PriceBookId = config.RCA_PricebookId__c;
        //System.debug(Rca_PriceBookId);
        //get all the new Quotes which are just migrated
        set<String> migratedQuoteNames = new set<String>(); // holds old quote names
        //all the new quotes list
        Map<String,Id> migatedQuotesIdToNameMap = new Map<String,Id>();
        List<Quote> newQuoteList = [select Id,Name from Quote where Name like 'RCA - %'];
        //slices the 'RCA - ' from new quote name and add it to the set
        for(Quote quote : newQuoteList){
            String oldquoteName = quote.Name.removeStart('RCA - ');
            migatedQuotesIdToNameMap.put(quote.Name,quote.Id);
            migratedQuoteNames.add(oldquoteName);
        }
        //stores the Sku and Id of migrated bundle products
        Map<String,Id> bundleProducts = new Map<String,Id>();
        for(Product2 prod : [select Id,StockKeepingUnit from Product2 where StockKeepingUnit Like '% - Bundle']){
            bundleProducts.put(prod.StockKeepingUnit,prod.Id);
        }
        
        //holds all the old Quotes
        List<SBQQ__Quote__c> oldQuoteList = [select Id,Name from SBQQ__Quote__c where Name IN :migratedQuoteNames];
        
        // Stores the old quotes Id's of quote and their products in quote lines
        Map<Id,List<Id>> oldQuoteToProducts = new Map<Id,List<Id>>();
        //collect all the products which are in oldquote it means all are old products
        List<Id> quotelineProductId = new List<Id>();
        
        List<SBQQ__QuoteLine__c> oldQuotelinesList = [select SBQQ__Product__c,SBQQ__AdditionalDiscountAmount__c,SBQQ__Discount__c,SBQQ__Quantity__c,SBQQ__Description__c,SBQQ__SubscriptionTerm__c,
                                                      SBQQ__EndDate__c,SBQQ__PartnerDiscount__c,SBQQ__Quote__r.Name,SBQQ__SegmentLabel__c,SBQQ__StartDate__c from SBQQ__QuoteLine__c where SBQQ__Quote__r.Name = 'Q-00005'];
        
        // stores quotes and their related quote lines in Map
        for(SBQQ__QuoteLine__c quoteline : oldQuotelinesList){
            quotelineProductId.add(quoteline.SBQQ__Product__c);
            if(oldQuoteToProducts.containsKey(quoteline.SBQQ__Quote__c)){
                oldQuoteToProducts.get(quoteline.SBQQ__Quote__c).add(quoteline.SBQQ__Product__c);
            }
            else{
                oldQuoteToProducts.put(quoteline.SBQQ__Quote__c,new List<Id>{quoteline.SBQQ__Product__c});
            }
        }
        
        // the above code 
        List<Product2> prouductsList = [select Id,StockKeepingUnit from Product2 where Id In :quotelineProductId];
        Map<Id,String> oldProductSkuToId = new Map<Id,String>();
        for(Product2 prod : prouductsList){
            oldProductSkuToId.put(prod.Id,prod.StockKeepingUnit);
        }
        //get the price book entry Ids of all the products
        Map<Id,Id> productToPricebookEntry = new Map<Id,Id>();
        List<PricebookEntry> pricebookEntryList = [select Id,Product2Id from PricebookEntry where Pricebook2Id =:Rca_PriceBookId];
        for(PricebookEntry pbe : pricebookEntryList){
            productToPricebookEntry.put(pbe.Product2Id,pbe.Id);
        }
        
        List<QuoteLineItem> newquotelineItemToInsert = new List<QuoteLineItem>();
        for(SBQQ__QuoteLine__c quoteline :oldQuotelinesList){
            QuoteLineItem item = new QuoteLineItem();
            item.DiscountAmount= quoteline.SBQQ__AdditionalDiscountAmount__c;
            item.Quantity = quoteline.SBQQ__Quantity__c;
            item.Description=quoteline.SBQQ__Description__c;
            item.EndDate = quoteline.SBQQ__EndDate__c;
            item.PartnerDiscountPercent=quoteline.SBQQ__PartnerDiscount__c;
            item.QuoteId=migatedQuotesIdToNameMap.get('RCA - '+quoteline.SBQQ__Quote__r.Name);
            item.SegmentName = quoteline.SBQQ__SegmentLabel__c;
            item.StartDate=quoteline.SBQQ__StartDate__c;
            item.Discount=quoteline.SBQQ__Discount__c;
            item.SubscriptionTerm=(Integer)quoteline.SBQQ__SubscriptionTerm__c;
           
            if(bundleProducts.containsKey(oldProductSkuToId.get(quoteline.SBQQ__Product__c)+' - Bundle')){
                item.Product2Id=bundleProducts.get(oldProductSkuToId.get(quoteline.SBQQ__Product__c)+' - Bundle');
                item.PricebookEntryId =productToPricebookEntry.get(item.Product2Id);
            }
            else{
                item.Product2Id=quoteline.SBQQ__Product__c;
                item.PricebookEntryId =productToPricebookEntry.get(item.Product2Id);
            }
            
            newquotelineItemToInsert.add(item);
        }
        for(QuoteLineItem quote : newquotelineItemToInsert){
            System.debug('new RCA Quote Id '+ quote.QuoteId);
            System.debug('new RCA product Id '+quote.Product2Id);
            System.debug('pricebookEntry Id '+quote.PricebookEntryId);
                }
        if(!newquotelineItemToInsert.isEmpty()){
            insert newquotelineItemToInsert;
        }
    }
}