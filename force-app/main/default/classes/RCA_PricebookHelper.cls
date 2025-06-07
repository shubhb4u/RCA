public class RCA_PricebookHelper {

    public static void createPricebookEntries(List<Product2> newBundleProductsList, String pricebookId, String psmoId) {
        if (newBundleProductsList.isEmpty()) return;

        // Step 1: Map new product SKUs to their IDs
        Map<String, Id> newSkuToIdMap = new Map<String, Id>();
        List<String> oldSkuList = new List<String>();
        for (Product2 product : newBundleProductsList) {
            newSkuToIdMap.put(product.StockKeepingUnit, product.Id);
            oldSkuList.add(product.StockKeepingUnit.remove(' - Bundle'));
        }

        // Step 2: Get old SKU to unit price mapping
        Map<String, Decimal> oldSkuToPriceMap = new Map<String, Decimal>();
        for (PricebookEntry entry : [
            SELECT Product2.StockKeepingUnit, UnitPrice
            FROM PricebookEntry
            WHERE Product2.StockKeepingUnit IN :oldSkuList
        ]) {
            oldSkuToPriceMap.put(entry.Product2.StockKeepingUnit, entry.UnitPrice);
        }

        // Step 3: Create ProductSellingModelOption entries
        List<ProductSellingModelOption> psmoList = new List<ProductSellingModelOption>();
        for (Product2 product : newBundleProductsList) {
            psmoList.add(new ProductSellingModelOption(
                Product2Id = product.Id,
                ProductSellingModelId = psmoId
            ));
        }
        insert psmoList;

        // Step 4: Map Product2Id to PSMO Id
        Map<Id, Id> productToPsmoMap = new Map<Id, Id>();
        for (ProductSellingModelOption psmo : psmoList) {
            productToPsmoMap.put(psmo.Product2Id, psmo.ProductSellingModelId);
        }

        // Step 5: Create PricebookEntry records
        List<PricebookEntry> entriesToInsert = new List<PricebookEntry>();
        for (Product2 product : newBundleProductsList) {
            String oldSku = product.StockKeepingUnit.remove(' - Bundle');
            Decimal price = oldSkuToPriceMap.get(oldSku);

            if (price != null) {
                entriesToInsert.add(new PricebookEntry(
                    Product2Id = product.Id,
                    UnitPrice = price,
                    Pricebook2Id = pricebookId,
                    ProductSellingModelId = productToPsmoMap.get(product.Id),
                    IsActive = true
                ));
            }
        }

        if (!entriesToInsert.isEmpty()) {
            insert entriesToInsert;
        }
    }
}