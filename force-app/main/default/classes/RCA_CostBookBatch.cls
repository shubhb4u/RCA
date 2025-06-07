public class RCA_CostBookBatch implements Database.Batchable<SObject> {

    public String costBookId;
    public Map<Id, Decimal> productToPriceMap;

    public RCA_CostBookBatch() {
        costBookId = RCA_CostBookHelper.getCostBookId();
        productToPriceMap = RCA_CostBookHelper.getProductToPriceMap();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, StockKeepingUnit 
            FROM Product2 
            WHERE Id IN :productToPriceMap.keySet()
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        List<CostBookEntry> costBookEntries = new List<CostBookEntry>();

        Map<String, Id> skuToProductId = RCA_CostBookHelper.getSkuToProductIdMap(scope);
        Set<String> bundleSKUs = RCA_CostBookHelper.getBundleSKUs(scope);

        // Entries for base products
        costBookEntries.addAll(RCA_CostBookHelper.createCostBookEntries(scope, productToPriceMap, costBookId));

        // Fetch bundle products
        List<Product2> bundleProducts = [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :bundleSKUs];

        // Entries for bundles
        costBookEntries.addAll(RCA_CostBookHelper.createBundleCostBookEntries(bundleProducts, skuToProductId, productToPriceMap, costBookId));

        if (!costBookEntries.isEmpty()) {
            insert costBookEntries;
        }
    }

    public void finish(Database.BatchableContext bc) {
    }
}