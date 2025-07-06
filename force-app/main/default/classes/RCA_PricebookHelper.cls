public class RCA_PricebookHelper {

    @TestVisible private static Boolean forceExceptionInTest = false;
    public  Id stdPB; 
    public  Id rcaPB;
    public  Id proId;
    public  String type = 'Bundle';
    public  Map<String, Id> psmMap = new Map<String, Id>(); 


    public RCA_PricebookHelper(){

        List<Pricebook2> stdPBList = [SELECT Id FROM PriceBook2 WHERE Name = 'Standard Price Book' LIMIT 1];
        if (!stdPBList.isEmpty()) {
            stdPB = stdPBList[0].Id;
        }

        List<Pricebook2> rcaPBList = [SELECT Id FROM PriceBook2 WHERE Name = 'RCA_PriceBook' LIMIT 1];
        if (!rcaPBList.isEmpty()) {
            rcaPB = rcaPBList[0].Id;
        }

        for(ProductSellingModel psm: [SELECT Id, Name, SellingModelType, PricingTermUnit, PricingTerm FROM ProductSellingModel]){
            if(!psmMap.containsKey(psm.SellingModelType)){
                String termUnit = String.isBlank(psm.PricingTermUnit) ? 'Months' : psm.PricingTermUnit;
                String key = psm.SellingModelType + termUnit;
                psmMap.put(key, psm.Id);
            }
        }

        List<ProrationPolicy> proList = [select id, name from ProrationPolicy where Name LIKE '%Default%' LIMIT 1];
        if(!proList.isEmpty()){
            proId = proList[0].Id;
        }

        // Now this condition will be covered safely
        if (String.isBlank(stdPB) || String.isBlank(rcaPB) ) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PricebookBatchVersion2',
                'processProducts',
                'Config',
                null,
                'Missing config values: stdPB=' + stdPB + ', rcaPB=' + rcaPB 
            );
            return;
        }
    }

    public void processProducts(List<Product2> products) {

        if (Test.isRunningTest() && forceExceptionInTest) {
             throw new AuraHandledException('Simulated exception for test coverage');
        }

        //1. Create PSMOs for all products as it is Mandate to create PBE's
        upsertPSMOs(products,  'old');
    
        // If Standalone products exist - 
        if (!products.isEmpty()) {
    
            Map<Id, List<PriceBookEntry>> existingStandardPBEs = getExistingPBEMap(products, new List<Id>{stdPB}, null);
            Map<Id, List<PriceBookEntry>> existingRCAPBEs = getExistingPBEMap(products, new List<Id>{rcaPB}, null);
    
            //If oldProducts have standard PBE, then just create a new RCA PBE - 
            List<PricebookEntry> stdPBEs = clonePBEs(products, stdPB, existingStandardPBEs, null);
            performDML(stdPBEs, 'Upsert: Standard PBEs (Old)', 'upsert');
    
            List<PricebookEntry> rcaPBEs = clonePBEs(products, rcaPB, existingStandardPBEs, existingRCAPBEs);
            performDML(rcaPBEs, 'Upsert: RCA PBEs (Old)', 'upsert');
        }
    }
    

    public void upsertPSMOs(List<Product2> products, String label) {
        if (products.isEmpty()) return;
    
        Map<String, Id> existing = new Map<String, Id>();
        //Most likely this will have on 1 record based on the behavior of product's subscription field.
        for (ProductSellingModelOption psmo : [SELECT Id, Product2Id, ProductSellingModelId FROM ProductSellingModelOption WHERE Product2Id IN :products ]) {
            String key = psmo.Product2Id + '-' + psmo.ProductSellingModelId;
            if(!existing.containsKey(key)){
                existing.put(key, psmo.Id);
            }
        }
    
        List<ProductSellingModelOption> toUpsert = new List<ProductSellingModelOption>();
    
        for (Product2 p : products) {
            ProductSellingModelOption opt = new ProductSellingModelOption();
            opt.Product2Id = p.Id;
    
            if (String.isBlank(p.SBQQ__SubscriptionType__c) ||
                String.isBlank(p.SBQQ__SubscriptionPricing__c)) {
                opt.ProductSellingModelId =  psmMap.get('OneTime'+'Months');
    
            } else if (p.SBQQ__SubscriptionType__c == 'Renewable') {
                opt.ProductSellingModelId = psmMap.get('TermDefined'+'Months');
                opt.ProrationPolicyId  = proId;
    
            } else if (p.SBQQ__SubscriptionType__c == 'Evergreen')  {
                opt.ProductSellingModelId = psmMap.get('Evergreen'+'Months');
                opt.ProrationPolicyId  = proId;

            } else if (p.SBQQ__SubscriptionType__c == 'One-Time')  {
                opt.ProductSellingModelId = psmMap.get('OneTime'+'Months');
            } 
    
            String duplicateKey = p.Id + '-' + opt.ProductSellingModelId;
            if (existing.containsKey(duplicateKey)) {
                opt.Id = existing.get(duplicateKey);
            }
            toUpsert.add(opt);
        }
        performDML(toUpsert, 'Upsert: ' + label + ' PSMOs', 'upsert');
    }    


    public Map<Id, List<PriceBookEntry>> getExistingPBEMap(List<Product2> products, List<Id> pbIds, String prodSKU) {
        String query = 'SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, productSellingModel.SellingModelType, UnitPrice, IsActive FROM PricebookEntry WHERE Pricebook2Id IN :pbIds';
        
        if (!String.isBlank(prodSKU)) {
            String originalSKU = prodSKU.replace(' - Bundle', '');
            query += ' AND Product2.StockKeepingUnit = :originalSKU';
        } else if (!products.isEmpty()) {
            query += ' AND Product2Id IN :products';
        }
    
        List<PricebookEntry> pbList = Database.query(query);
        Map<Id, List<PriceBookEntry>> existingMap = new Map<Id, List<PriceBookEntry>>();
    
        for (PricebookEntry pbe : pbList) {
            if (!existingMap.containsKey(pbe.Product2Id)) {
                existingMap.put(pbe.Product2Id, new List<PriceBookEntry>());
            }
            existingMap.get(pbe.Product2Id).add(pbe);
        }
    
        return existingMap;
    }
    

    //Create standard PriceBookEntries and RCA PriceBook Entries with correct PSMOs created in previous step - 
    public List<PricebookEntry> clonePBEs(List<Product2> products, Id pbId, Map<Id, List<PriceBookEntry>> existingStandardMap, Map<Id, List<PriceBookEntry>> existingRCAMap) {
        List<PricebookEntry> cloneList = new List<PricebookEntry>();
    
        System.debug('Cloning PBEs for Pricebook ID: ' + pbId);
        System.debug('Total products to process: ' + products.size());
    
        for (Product2 prod : products) {
            System.debug('Processing Product2: ' + prod.Id + ' | SKU: ' + prod.StockKeepingUnit);
    
            List<PricebookEntry> existingPBEs = existingStandardMap.get(prod.Id);

            // Fallback for newly created Bundle products that may not have standard PBEs, so get it from their old Product2 record
            if (prod.Type == 'Bundle') {
                Map<Id, List<PriceBookEntry>> oldPBEMap = getExistingPBEMap(new List<Product2>(), new List<Id>{stdPB}, prod.StockKeepingUnit);
                existingPBEs = oldPBEMap.isEmpty() ? null : oldPBEMap.values().get(0); // pick the list from the map
            }

            if (existingPBEs == null || existingPBEs.isEmpty()) {
                System.debug('No PBEs found for Product2 (even after fallback): ' + prod.Id);
                continue;
            }
    
            Decimal unitPrice = null;
            Boolean isActive = true;
    
            // Get unit price from the standard PBE (without a PSM)
            for (PricebookEntry pbe : existingPBEs) {
                if (pbe.ProductSellingModelId == null) {
                    unitPrice = pbe.UnitPrice;
                    isActive = pbe.IsActive;
                    System.debug('Base PBE found: unitPrice=' + unitPrice + ', isActive=' + isActive + ' for Product2: ' + prod.Id);
                    break;
                }
            }
    
            if (unitPrice == null) {
                System.debug('No base PBE without ProductSellingModelId found for Product2: ' + prod.Id);
                continue;
            }
    
            // Determine the PSM key
            String key;
            if (String.isBlank(prod.SBQQ__SubscriptionType__c) || String.isBlank(prod.SBQQ__SubscriptionPricing__c)) {
                key = 'OneTimeMonths';
            } else if (prod.SBQQ__SubscriptionType__c == 'Renewable') {
                key = 'TermDefinedMonths';
            } else if (prod.SBQQ__SubscriptionType__c == 'Evergreen') {
                key = 'EvergreenMonths';
            } else if (prod.SBQQ__SubscriptionType__c == 'One-Time') {
                key = 'OneTimeMonths';
            } else {
                System.debug('Unhandled SubscriptionType: ' + prod.SBQQ__SubscriptionType__c + ' for Product2: ' + prod.Id);
                continue;
            }
    
            Id finalPSMId = psmMap.get(key);
            System.debug('Derived PSM key: ' + key + ', finalPSMId: ' + finalPSMId);
    
            if (finalPSMId == null) {
                System.debug('No PSM found for key: ' + key + ' | Product2: ' + prod.Id);
                continue;
            }

            Boolean alreadyExists = false;
    
            // Standard path: If RCA map is null, it indicates we're first creating standard PBEs only
            if (existingRCAMap == null) {
                
                for (PricebookEntry existing : existingPBEs) {
                    if (existing.Pricebook2Id == pbId && existing.ProductSellingModelId == finalPSMId) {
                        System.debug('Standard PBE already exists for Product2: ' + prod.Id + ', skipping clone.');
                        alreadyExists = true;
                        cloneList.add(existing);
                        break;
                    }
                }
            } 
            // RCA path: check RCA PBEs to avoid duplicates, base price from standard
            else {
                List<PricebookEntry> existingRCAPBEs = existingRCAMap.get(prod.Id);
                // Boolean alreadyExists = false;
    
                if (existingRCAPBEs != null) {
                    for (PricebookEntry existing : existingRCAPBEs) {
                        if (existing.Pricebook2Id == pbId && existing.ProductSellingModelId == finalPSMId) {
                            System.debug('RCA PBE already exists for Product2: ' + prod.Id + ', skipping clone.');
                            alreadyExists = true;
                            cloneList.add(existing);
                            break;
                        }
                    }
                }
            }

            if (!alreadyExists) {
                PricebookEntry newPBE = new PricebookEntry(
                    Product2Id = prod.Id,
                    Pricebook2Id = pbId,
                    ProductSellingModelId = finalPSMId,
                    UnitPrice = unitPrice,
                    IsActive = isActive
                );
                cloneList.add(newPBE);
                System.debug('Cloned new RCA PBE for Product2: ' + prod.Id + ' | PricebookId: ' + pbId);
            }
        }
    
        System.debug('Total PBEs cloned/returned: ' + cloneList.size());
        return cloneList;
    }
    

    public void performDML(List<SObject> dmlList, String context, String option) {
        if (dmlList.isEmpty()) return;
    
        try {
            Database.UpsertResult[] results = Database.upsert(dmlList, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String sObjectType = dmlList[i].getSObjectType().getDescribe().getName(); // ✅ get type from original record
                    RCA_BatchExceptionLogger.logExceptions(
                        'RCA_PricebookBatchVersion2',
                        context,
                        sObjectType,
                        results[i].getErrors(),
                        JSON.serialize(results[i])
                    );
                }
            }
        } catch (Exception e) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PricebookBatchVersion2',
                context,
                'DML_Exception',
                null,
                e.getMessage()
            );
        }
    }    

}
