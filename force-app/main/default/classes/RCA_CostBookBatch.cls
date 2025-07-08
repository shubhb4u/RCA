public class RCA_CostBookBatch implements Database.Batchable<SObject> {

    public String costBookId;
    public Map<Id, Decimal> productToPriceMap;
    public List<Id> productIds;

    public RCA_CostBookBatch() {
        costBookId = RCA_CostBookHelper.getCostBookId();
        productToPriceMap = RCA_CostBookHelper.getProductToPriceMap();
        productIds = new List<Id>(productToPriceMap.keySet()); 
    }

    public RCA_CostBookBatch(List<Id> productIds) {
        this.costBookId = RCA_CostBookHelper.getCostBookId();
        this.productToPriceMap = RCA_CostBookHelper.getProductToPriceMap();

        // Use provided productIds if not null/empty, else default to all products from the map
        if (productIds != null && !productIds.isEmpty()) {
            this.productIds = productIds;
        } else {
            this.productIds = new List<Id>(productToPriceMap.keySet());
        }
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, StockKeepingUnit 
            FROM Product2 
            WHERE Id IN :productIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Product2> scope) {
        List<CostBookEntry> costBookEntries = new List<CostBookEntry>();

        Map<String, Id> skuToProductId = RCA_CostBookHelper.getSkuToProductIdMap(scope);
        Set<String> bundleSKUs = RCA_CostBookHelper.getBundleSKUs(scope);

        // Entries for base products
        costBookEntries.addAll(RCA_CostBookHelper.createCostBookEntries(scope, productToPriceMap, costBookId));

        // Fetch bundle products
        List<Product2> bundleProducts = [
            SELECT Id, StockKeepingUnit 
            FROM Product2 
            WHERE StockKeepingUnit IN :bundleSKUs
        ];

        // Entries for bundles
        costBookEntries.addAll(RCA_CostBookHelper.createBundleCostBookEntries(bundleProducts, skuToProductId, productToPriceMap, costBookId));

        if (!costBookEntries.isEmpty()) {
            insert costBookEntries;
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('RCA_CostBookBatch finished successfully.');
    }
}