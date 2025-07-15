public class RCA_PricebookHelper {

    @TestVisible private static Boolean forceExceptionInTest = false;
    public Id stdPB; 
    public List<Id> customPBIds = new List<Id>();
    public Id proId;
    public String type = 'Bundle';
    public Map<String, Id> psmMap = new Map<String, Id>(); 

    public RCA_PricebookHelper(){
        // Get Standard Price Book
        List<Pricebook2> stdPBList = [SELECT Id FROM PriceBook2 WHERE Name = 'Standard Price Book' LIMIT 1];
        if (!stdPBList.isEmpty()) {
            stdPB = stdPBList[0].Id;
        }

        // Get all custom pricebooks (excluding Standard Price Book)
        List<Pricebook2> customPBList = [SELECT Id, Name FROM PriceBook2 WHERE Name != 'Standard Price Book' AND IsActive = true];
        for(Pricebook2 pb : customPBList) {
            customPBIds.add(pb.Id);
        }

        // Build Product Selling Model map
        for(ProductSellingModel psm: [SELECT Id, Name, SellingModelType, PricingTermUnit, PricingTerm FROM ProductSellingModel]){
            if(!psmMap.containsKey(psm.SellingModelType)){
                String termUnit = String.isBlank(psm.PricingTermUnit) ? 'Months' : psm.PricingTermUnit;
                String key = psm.SellingModelType + termUnit;
                psmMap.put(key, psm.Id);
            }
        }

        // Get default proration policy
        List<ProrationPolicy> proList = [select id, name from ProrationPolicy where Name LIKE '%Default%' LIMIT 1];
        if(!proList.isEmpty()){
            proId = proList[0].Id;
        }

        // Validation - now checking for custom pricebooks instead of specific RCA pricebook
        if (String.isBlank(stdPB) || customPBIds.isEmpty() || String.isBlank(proId) || psmMap.isEmpty()) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_PricebookBatchVersion2',
                'processProducts',
                'Config',
                null,
                'Missing config values: stdPB=' + stdPB + ', customPBIds=' + customPBIds + ', proId=' + proId + ', psmMap=' + psmMap
            );
            return;
        }
    }

    public void processProducts(List<Product2> products) {
        if (Test.isRunningTest() && forceExceptionInTest) {
             throw new AuraHandledException('Simulated exception for test coverage');
        }
    
        if (!products.isEmpty()) {
            //1. Create PSMOs for all products as it is Mandate to create PBE's
            upsertPSMOs(products, 'products');
    
            // Get existing PBEs from all pricebooks (standard + custom)
            List<Id> allPBIds = new List<Id>{stdPB};
            allPBIds.addAll(customPBIds);
            
            Map<Id, List<PriceBookEntry>> existingAllPBEs = getExistingPBEMap(products, allPBIds, null);
    
            // Step 1: Create/Update Standard PBEs first
            List<PricebookEntry> stdPBEs = createStandardPBEs(products, existingAllPBEs);
            performDML(stdPBEs, 'Upsert: Standard PBEs', 'upsert');
    
            // Step 2: Create/Update Custom PBEs for all custom pricebooks
            List<PricebookEntry> customPBEs = createCustomPBEs(products, existingAllPBEs);
            performDML(customPBEs, 'Upsert: Custom PBEs', 'upsert');
        }
    }
    
    public void upsertPSMOs(List<Product2> products, String label) {
        if (products.isEmpty()) return;
    
        Map<String, Id> existing = new Map<String, Id>();
        for (ProductSellingModelOption psmo : [SELECT Id, Product2Id, ProductSellingModelId FROM ProductSellingModelOption WHERE Product2Id IN :products]) {
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
                opt.ProductSellingModelId = psmMap.get('OneTime'+'Months');
            } else if (p.SBQQ__SubscriptionType__c == 'Renewable') {
                opt.ProductSellingModelId = psmMap.get('TermDefined'+'Months');
                opt.ProrationPolicyId = proId;
            } else if (p.SBQQ__SubscriptionType__c == 'Evergreen') {
                opt.ProductSellingModelId = psmMap.get('Evergreen'+'Months');
                opt.ProrationPolicyId = proId;
            } else if (p.SBQQ__SubscriptionType__c == 'One-Time') {
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
    
    // New method to create Standard PBEs
    public List<PricebookEntry> createStandardPBEs(List<Product2> products, Map<Id, List<PriceBookEntry>> existingAllPBEs) {
        List<PricebookEntry> standardPBEs = new List<PricebookEntry>();
        
        System.debug('Creating Standard PBEs for ' + products.size() + ' products');
        
        for (Product2 prod : products) {
            System.debug('Processing Product2: ' + prod.Id + ' | SKU: ' + prod.StockKeepingUnit);
            
            List<PricebookEntry> existingPBEs = existingAllPBEs.get(prod.Id);
            
            // Fallback for Bundle products
            if (prod.Type == 'Bundle' && (existingPBEs == null || existingPBEs.isEmpty())) {
                List<Id> allPBIds = new List<Id>{stdPB};
                allPBIds.addAll(customPBIds);
                Map<Id, List<PriceBookEntry>> oldPBEMap = getExistingPBEMap(new List<Product2>(), allPBIds, prod.StockKeepingUnit);
                existingPBEs = oldPBEMap.isEmpty() ? null : oldPBEMap.values().get(0);
            }
            
            if (existingPBEs == null || existingPBEs.isEmpty()) {
                System.debug('No existing PBEs found for Product2: ' + prod.Id);
                continue;
            }
            
            // Find unit price from any existing PBE (prioritize standard, then custom)
            Decimal unitPrice = null;
            Boolean isActive = true;
            
            // First try to get price from standard PBE
            for (PricebookEntry pbe : existingPBEs) {
                if (pbe.Pricebook2Id == stdPB && pbe.ProductSellingModelId == null) {
                    unitPrice = pbe.UnitPrice;
                    isActive = pbe.IsActive;
                    break;
                }
            }
            
            // If no standard PBE found, get from any custom PBE
            if (unitPrice == null) {
                for (PricebookEntry pbe : existingPBEs) {
                    if (pbe.ProductSellingModelId == null) {
                        unitPrice = pbe.UnitPrice;
                        isActive = pbe.IsActive;
                        break;
                    }
                }
            }
            
            if (unitPrice == null) {
                System.debug('No base PBE found for Product2: ' + prod.Id);
                continue;
            }
            
            // Get the appropriate PSM ID
            String psmKey = getPSMKey(prod);
            Id finalPSMId = psmMap.get(psmKey);
            
            if (finalPSMId == null) {
                System.debug('No PSM found for key: ' + psmKey + ' | Product2: ' + prod.Id);
                continue;
            }
            
            // Check if standard PBE already exists
            Boolean alreadyExists = false;
            for (PricebookEntry existing : existingPBEs) {
                if (existing.Pricebook2Id == stdPB && existing.ProductSellingModelId == finalPSMId) {
                    System.debug('Standard PBE already exists for Product2: ' + prod.Id);
                    alreadyExists = true;
                    standardPBEs.add(existing);
                    break;
                }
            }
            
            if (!alreadyExists) {
                PricebookEntry newPBE = new PricebookEntry(
                    Product2Id = prod.Id,
                    Pricebook2Id = stdPB,
                    ProductSellingModelId = finalPSMId,
                    UnitPrice = unitPrice,
                    IsActive = isActive
                );
                standardPBEs.add(newPBE);
                System.debug('Created new Standard PBE for Product2: ' + prod.Id);
            }
        }
        
        System.debug('Total Standard PBEs created/returned: ' + standardPBEs.size());
        return standardPBEs;
    }
    
    // New method to create Custom PBEs for all custom pricebooks
    public List<PricebookEntry> createCustomPBEs(List<Product2> products, Map<Id, List<PriceBookEntry>> existingAllPBEs) {
        List<PricebookEntry> customPBEs = new List<PricebookEntry>();
    
        for (Product2 prod : products) {
            List<PricebookEntry> existingPBEs = existingAllPBEs.get(prod.Id);
            
            // Fallback for Bundle products
            if (prod.Type == 'Bundle' && (existingPBEs == null || existingPBEs.isEmpty())) {
                List<Id> allPBIds = new List<Id>{stdPB};
                allPBIds.addAll(customPBIds);
                Map<Id, List<PriceBookEntry>> oldPBEMap = getExistingPBEMap(new List<Product2>(), allPBIds, prod.StockKeepingUnit);
                existingPBEs = oldPBEMap.isEmpty() ? null : oldPBEMap.values().get(0);
            }
    
            if (existingPBEs == null || existingPBEs.isEmpty()) {
                continue;
            }
    
            // Step 1: Get the pricebooks where the product already exists (base PBE)
            Set<Id> existingPBIdsForProduct = new Set<Id>();
            for (PricebookEntry pbe : existingPBEs) {
                if (pbe.ProductSellingModelId == null) {
                    existingPBIdsForProduct.add(pbe.Pricebook2Id);
                }
            }
    
            // Step 2: Create RCA PBEs only for those pricebooks
            for (Id pbId : existingPBIdsForProduct) {
                // Skip standard pricebook
                if (pbId == stdPB) continue;
    
                Decimal unitPrice;
                Boolean isActive = true;
    
                for (PricebookEntry pbe : existingPBEs) {
                    if (pbe.Pricebook2Id == pbId && pbe.ProductSellingModelId == null) {
                        unitPrice = pbe.UnitPrice;
                        isActive = pbe.IsActive;
                        break;
                    }
                }
    
                if (unitPrice == null) continue;
    
                // Get the appropriate PSM ID
                String psmKey = getPSMKey(prod);
                Id finalPSMId = psmMap.get(psmKey);
                if (finalPSMId == null) continue;
    
                // Check if RCA PBE already exists
                Boolean alreadyExists = false;
                for (PricebookEntry pbe : existingPBEs) {
                    if (pbe.Pricebook2Id == pbId && pbe.ProductSellingModelId == finalPSMId) {
                        alreadyExists = true;
                        customPBEs.add(pbe); // include existing
                        break;
                    }
                }
    
                if (!alreadyExists) {
                    PricebookEntry newPBE = new PricebookEntry(
                        Product2Id = prod.Id,
                        Pricebook2Id = pbId,
                        ProductSellingModelId = finalPSMId,
                        UnitPrice = unitPrice,
                        IsActive = isActive,
                        Is_RCA_Entry__c = true
                    );
                    customPBEs.add(newPBE);
                }
            }
        }
    
        return customPBEs;
    }
    
    
    // Helper method to get PSM key based on product subscription type
    public String getPSMKey(Product2 prod) {
        if (String.isBlank(prod.SBQQ__SubscriptionType__c) || String.isBlank(prod.SBQQ__SubscriptionPricing__c)) {
            return 'OneTimeMonths';
        } else if (prod.SBQQ__SubscriptionType__c == 'Renewable') {
            return 'TermDefinedMonths';
        } else if (prod.SBQQ__SubscriptionType__c == 'Evergreen') {
            return 'EvergreenMonths';
        } else if (prod.SBQQ__SubscriptionType__c == 'One-Time') {
            return 'OneTimeMonths';
        }
        return 'OneTimeMonths'; // default
    }

    public void performDML(List<SObject> dmlList, String context, String option) {
        if (dmlList.isEmpty()) return;
    
        try {
            Database.UpsertResult[] results = Database.upsert(dmlList, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    String sObjectType = dmlList[i].getSObjectType().getDescribe().getName(); 
                    RCA_BatchExceptionLogger.logExceptions(
                        'RCA_Pricebook',
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