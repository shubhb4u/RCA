public class RCA_CostBookHelper {

    public static String getCostBookId() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return config != null ? config.CostBook__c : null;
    }

    public static Map<Id, Decimal> getProductToPriceMap() {
        Map<Id, Decimal> productToPriceMap = new Map<Id, Decimal>();
        for (SBQQ__Cost__c cost : [SELECT SBQQ__Product__c, SBQQ__UnitCost__c FROM SBQQ__Cost__c]) {
            productToPriceMap.put(cost.SBQQ__Product__c, cost.SBQQ__UnitCost__c);
        }
        return productToPriceMap;
    }

    public static Map<String, Id> getSkuToProductIdMap(List<Product2> products) {
        Map<String, Id> skuMap = new Map<String, Id>();
        for (Product2 product : products) {
            skuMap.put(product.StockKeepingUnit, product.Id);
        }
        return skuMap;
    }

    public static Set<String> getBundleSKUs(List<Product2> products) {
        Set<String> bundleSKUs = new Set<String>();
        for (Product2 product : products) {
            bundleSKUs.add(product.StockKeepingUnit + 'Bundle');
        }
        return bundleSKUs;
    }

    public static List<CostBookEntry> createCostBookEntries(List<Product2> baseProducts, Map<Id, Decimal> productToPriceMap, String costBookId) {
        List<CostBookEntry> entries = new List<CostBookEntry>();
        for (Product2 product : baseProducts) {
            entries.add(new CostBookEntry(
                CostBookId = costBookId,
                ProductId = product.Id,
                Cost = productToPriceMap.get(product.Id),
                EffectiveFrom = DateTime.now()
            ));
        }
        return entries;
    }

    public static List<CostBookEntry> createBundleCostBookEntries(List<Product2> bundleProducts, Map<String, Id> baseSkuToId, Map<Id, Decimal> productToPriceMap, String costBookId) {
        List<CostBookEntry> entries = new List<CostBookEntry>();
        for (Product2 bundle : bundleProducts) {
            String baseSku = bundle.StockKeepingUnit.remove('Bundle');
            Id baseProductId = baseSkuToId.get(baseSku);
            Decimal baseCost = productToPriceMap.get(baseProductId);

            entries.add(new CostBookEntry(
                CostBookId = costBookId,
                ProductId = bundle.Id,
                Cost = baseCost,
                EffectiveFrom = DateTime.now()
            ));
        }
        return entries;
    }
}