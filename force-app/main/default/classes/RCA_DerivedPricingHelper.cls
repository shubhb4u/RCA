public class RCA_DerivedPricingHelper {
    
    public static void processDerivedPricing() {
        // Step 1: Get POT products
        List<Product2> potProducts = [
            SELECT Id, Name, StockKeepingUnit, SBQQ__SubscriptionPercent__c, SBQQ__SubscriptionBase__c
            FROM Product2
            WHERE SBQQ__PricingMethod__c = 'Percent Of Total' AND SBQQ__SubscriptionBase__c = 'Net'
        ];

        List<Id> potProductIds = new List<Id>();
        Map<Id, Decimal> productIdToPercentMap = new Map<Id, Decimal>();
        Map<String, Id> skuToProductIdMap = new Map<String, Id>();

        for (Product2 p : potProducts) {
            potProductIds.add(p.Id);
            productIdToPercentMap.put(p.Id, p.SBQQ__SubscriptionPercent__c);
            skuToProductIdMap.put(p.StockKeepingUnit, p.Id);
        }

        // Step 2: Delete old PricebookEntry records
        List<PricebookEntry> oldPBEs = [
            SELECT Id, IsActive, ProductSellingModelId, Product2Id
            FROM PricebookEntry
            WHERE Product2Id IN :potProductIds
        ];
        delete oldPBEs;

        // Step 3: Create new PricebookEntry records
        List<PricebookEntry> newPBEs = new List<PricebookEntry>();
        for (PricebookEntry oldEntry : oldPBEs) {
            PricebookEntry newEntry = new PricebookEntry();
            newEntry.IsActive = oldEntry.IsActive;
            newEntry.IsDerived = true;
            newEntry.ProductSellingModelId = oldEntry.ProductSellingModelId;
            newEntry.UnitPrice = 0;
            newEntry.Pricebook2Id = '01sKj000002skGhIAI'; // Replace if needed
            newEntry.Product2Id = oldEntry.Product2Id;
            newPBEs.add(newEntry);
        }
        insert newPBEs;

        // Step 4: Create derived prices for new entries
        List<PriceBookEntryDerivedPrice> derivedPrices = new List<PriceBookEntryDerivedPrice>();
        for (PricebookEntry newEntry : newPBEs) {
            Decimal percent = productIdToPercentMap.get(newEntry.Product2Id);
            if (percent != null) {
                Decimal decimalPercent = percent / 100;
                PriceBookEntryDerivedPrice dp = new PriceBookEntryDerivedPrice();
                dp.DerivedPricingScope = 'Transactional';
                dp.PricingSource = 'Header';
                dp.PricebookEntryId = newEntry.Id;
                dp.Formula = 'HeaderTotal * ' + String.valueOf(decimalPercent);
                dp.EffectiveFrom = Date.today();
                derivedPrices.add(dp);
            }
        }

        // Step 5: Handle bundle products
        List<Product2> bundleProducts = [
            SELECT Id, StockKeepingUnit
            FROM Product2
            WHERE Type = 'Bundle'
        ];

        List<PricebookEntry> newBundlePBEs = new List<PricebookEntry>();
        Map<Id, Id> bundleToBaseProductMap = new Map<Id, Id>();

        for (Product2 bundle : bundleProducts) {
            String baseSku = bundle.StockKeepingUnit.replace('Bundle', '');
            if (skuToProductIdMap.containsKey(baseSku)) {
                Id baseProductId = skuToProductIdMap.get(baseSku);

                PricebookEntry newBundleEntry = new PricebookEntry();
                newBundleEntry.IsActive = true;
                newBundleEntry.IsDerived = true;
                newBundleEntry.UnitPrice = 0;
                newBundleEntry.ProductSellingModelId = null;
                newBundleEntry.Pricebook2Id = '01sKj000002skGhIAI';
                newBundleEntry.Product2Id = bundle.Id;
                newBundlePBEs.add(newBundleEntry);

                bundleToBaseProductMap.put(bundle.Id, baseProductId);
            }
        }
        insert newBundlePBEs;

        // Step 6: Derived pricing for bundles
        for (PricebookEntry newEntry : newBundlePBEs) {
            Id baseProductId = bundleToBaseProductMap.get(newEntry.Product2Id);
            Decimal percent = productIdToPercentMap.get(baseProductId);
            if (percent != null) {
                Decimal decimalPercent = percent / 100;
                PriceBookEntryDerivedPrice dp = new PriceBookEntryDerivedPrice();
                dp.DerivedPricingScope = 'Transactional';
                dp.PricingSource = 'Header';
                dp.PricebookEntryId = newEntry.Id;
                dp.Formula = 'HeaderTotal * ' + String.valueOf(decimalPercent);
                dp.EffectiveFrom = Date.today();
                derivedPrices.add(dp);
            }
        }

        // Step 7: Insert all derived prices
        insert derivedPrices;
    }
}