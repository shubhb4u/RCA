public class RCA_DerivedPricingHelper {
    
    public List<Id> potProductIds = new List<Id>();
    public Map<Id, Decimal> productIdToPercentMap = new Map<Id, Decimal>();
    public Map<String, Id> skuToProductIdMap = new Map<String, Id>();
    public List<PricebookEntry> newPBEs = new List<PricebookEntry>();
    public List<PricebookEntry> newBundlePBEs = new List<PricebookEntry>();
    public List<PriceBookEntryDerivedPrice> derivedPrices = new List<PriceBookEntryDerivedPrice>();
    public Map<Id, Id> bundleToBaseProductMap = new Map<Id, Id>();
    
    public void collectPOTData(List<Product2> potProducts) {
        for (Product2 p : potProducts) {
            potProductIds.add(p.Id);
            productIdToPercentMap.put(p.Id, p.SBQQ__SubscriptionPercent__c);
            skuToProductIdMap.put(p.StockKeepingUnit, p.Id);
        }
    }
    
    public void deleteOldPBEs() {
        try {
            List<PricebookEntry> oldPBEs = [SELECT Id FROM PricebookEntry WHERE Product2Id IN :potProductIds];
            if (!oldPBEs.isEmpty()) delete oldPBEs;
        } catch (Exception e) {
            System.debug('Error deleting old PBEs: ' + e.getMessage());
        }
    }
    
    public void insertNewPBEs() {
        for (Id pid : potProductIds) {
            newPBEs.add(new PricebookEntry(
                IsActive=true,
                IsDerived=true,
                UnitPrice=0,
                Pricebook2Id='01sKj000002skGhIAI',
                Product2Id=pid
            ));
        }
        
        try {
            if (!newPBEs.isEmpty()) insert newPBEs;
        } catch (Exception e) {
            System.debug('Error inserting new PBEs: ' + e.getMessage());
        }
    }
    
    public void createDerivedPricesForNewPBEs() {
        for (PricebookEntry entry : newPBEs) {
            Decimal percent = productIdToPercentMap.get(entry.Product2Id);
            if (percent != null) {
                derivedPrices.add(new PriceBookEntryDerivedPrice(
                    DerivedPricingScope = 'Transactional',
                    PricingSource = 'Header',
                    PricebookEntryId = entry.Id,
                    PricebookId = entry.Pricebook2Id,
                    Formula = 'HeaderTotal * ' + String.valueOf(percent / 100),
                    EffectiveFrom = Date.today()
                ));
            }
        }
    }
    
    public void prepareAndInsertBundlePBEs() {
        List<Product2> bundleProducts = [
            SELECT Id, StockKeepingUnit FROM Product2 WHERE Type = 'Bundle'
        ];
        
        for (Product2 bundle : bundleProducts) {
            if(bundle.StockKeepingUnit!=null){
                String baseSku = bundle.StockKeepingUnit.replace('Bundle', '');
                if (skuToProductIdMap.containsKey(baseSku)) {
                    Id baseId = skuToProductIdMap.get(baseSku);
                    
                    newBundlePBEs.add(new PricebookEntry(
                        IsActive=true,
                        IsDerived=true,
                        UnitPrice=0,
                        Pricebook2Id='01sKj000002skGhIAI',
                        Product2Id=bundle.Id
                    ));
                    
                    bundleToBaseProductMap.put(bundle.Id, baseId);
                }}
        }
        
        try {
            if (!newBundlePBEs.isEmpty()) insert newBundlePBEs;
        } catch (Exception e) {
            System.debug('Error inserting bundle PBEs: ' + e.getMessage());
        }
    }
    
    public void createDerivedPricesForBundles() {
        for (PricebookEntry entry : newBundlePBEs) {
            Id baseId = bundleToBaseProductMap.get(entry.Product2Id);
            Decimal percent = productIdToPercentMap.get(baseId);
            if (percent != null) {
                derivedPrices.add(new PriceBookEntryDerivedPrice(
                    DerivedPricingScope = 'Transactional',
                    PricingSource = 'Header',
                    PricebookEntryId = entry.Id,
                    PricebookId = entry.Pricebook2Id,
                    Formula = 'HeaderTotal * ' + String.valueOf(percent / 100),
                    EffectiveFrom = Date.today()
                ));
            }
        }
    }
    
    public void insertDerivedPrices() {
        try {
            if (!derivedPrices.isEmpty()) {
                insert derivedPrices;
            }
        } catch (Exception e) {
            System.debug('Error inserting derived prices: ' + e.getMessage());
        }
    }
}