global class RCA_PricebookBatch implements Database.Batchable<SObject> {

    global String pricebookId;
    global String productType;
    global String psmoId;

    global RCA_PricebookBatch() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        pricebookId = config.Standard_Price_book__c;
        productType = config.ProductType__c;
        psmoId = config.One_Time_Selling_Model__c;
    }

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Name, StockKeepingUnit
            FROM Product2
            WHERE Type = :productType
        ]);
    }

    global void execute(Database.BatchableContext bc, List<Product2> newBundleProductsList) {
        RCA_PricebookHelper.createPricebookEntries(newBundleProductsList, pricebookId, psmoId);
    }

    global void finish(Database.BatchableContext bc) {
        // optional post-processing
    }
}