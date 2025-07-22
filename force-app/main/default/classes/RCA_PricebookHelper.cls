public class RCA_PricebookHelper {

    @TestVisible private static Boolean forceExceptionInTest = false;
    public Id stdPB; 
    public List<Id> customPBIds = new List<Id>();
    public List<Id> rcaPBIds = new List<Id>(); // New: RCA Pricebook IDs
    public Id proId;
    public String type = 'Bundle';
    public Map<String, Id> psmMap = new Map<String, Id>(); 

    public RCA_PricebookHelper(){
        // Get Standard Price Book
        List<Pricebook2> stdPBList = [SELECT Id FROM Pricebook2 WHERE Name = 'Standard Price Book' LIMIT 1];
        if (!stdPBList.isEmpty()) {
            stdPB = stdPBList[0].Id;
        }

        // Get all custom pricebooks (excluding Standard Price Book and RCA pricebooks)
        List<Pricebook2> customPBList = [SELECT Id, Name FROM Pricebook2 WHERE Name != 'Standard Price Book' AND (NOT Name LIKE 'RCA_%') AND IsActive = true];
        for(Pricebook2 pb : customPBList) {
            customPBIds.add(pb.Id);
        }

        // Get existing RCA pricebooks
        List<Pricebook2> rcaPBList = [SELECT Id, Name FROM Pricebook2 WHERE Name LIKE 'RCA_%' AND IsActive = true];
        for(Pricebook2 pb : rcaPBList) {
            rcaPBIds.add(pb.Id);
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
                'RCA_Pricebook',
                'processProducts',
                'Config',
                null,
                'Missing config values: stdPB=' + stdPB + ', customPBIds=' + customPBIds + ', proId=' + proId + ', psmMap=' + psmMap
            );
            return;
        }
    }

    // New method to create RCA pricebooks based on existing custom pricebooks
    public void createRCAPricebooks() {
        // Get existing custom pricebooks with their details
        List<Pricebook2> customPBList = [SELECT Id, Name, Description, IsActive FROM Pricebook2 WHERE Id IN :customPBIds];
        
        // Get existing RCA pricebooks to avoid duplicates
        Set<String> existingRCANames = new Set<String>();
        for(Pricebook2 rcaPB : [SELECT Name FROM Pricebook2 WHERE Name LIKE 'RCA_%']) {
            existingRCANames.add(rcaPB.Name);
        }
        
        List<Pricebook2> newRCAPricebooks = new List<Pricebook2>();
        
        for(Pricebook2 customPB : customPBList) {
            String rcaName = 'RCA_' + customPB.Name;
            
            // Check if RCA pricebook already exists
            if(!existingRCANames.contains(rcaName)) {
                Pricebook2 newRCAPB = new Pricebook2(
                    Name = rcaName,
                    Description = 'RCA version of ' + customPB.Name,
                    IsActive = true
                );
                newRCAPricebooks.add(newRCAPB);
            }
        }
        
        if(!newRCAPricebooks.isEmpty()) {
            performDML(newRCAPricebooks, 'Insert: RCA Pricebooks', 'insert');
            
            // Update rcaPBIds with newly created pricebooks
            for(Pricebook2 newRCAPB : newRCAPricebooks) {
                if(newRCAPB.Id != null) {
                    rcaPBIds.add(newRCAPB.Id);
                }
            }
        }
    }

    // Enhanced main process method
    public void processProducts(List<Product2> products) {
        if (Test.isRunningTest() && forceExceptionInTest) {
             throw new AuraHandledException('Simulated exception for test coverage');
        }
    
        if (!products.isEmpty()) {
            // Step 1: Create RCA pricebooks if they don't exist
            createRCAPricebooks();
            
            // Step 2: Create PSMOs for all products as it is Mandate to create PBE's
            upsertPSMOs(products, 'products');
    
            // Get existing PBEs from all pricebooks (standard + custom + RCA)
            List<Id> allPBIds = new List<Id>{stdPB};
            allPBIds.addAll(customPBIds);
            allPBIds.addAll(rcaPBIds);
            
            Map<Id, List<PriceBookEntry>> existingAllPBEs = getExistingPBEMap(products, allPBIds, null);
    
            // Step 3: Create/Update Standard PBEs first
            List<PricebookEntry> stdPBEs = createStandardPBEs(products, existingAllPBEs);
            performDML(stdPBEs, 'Upsert: Standard PBEs', 'upsert');
    
            // Step 4: Create/Update RCA PBEs ONLY for RCA pricebooks where product has existing entries
            List<PricebookEntry> rcaPBEs = createRCAPBEs(products, existingAllPBEs);
            performDML(rcaPBEs, 'Upsert: RCA PBEs', 'upsert');
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
                allPBIds.addAll(rcaPBIds);
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
    
    //Create RCA PBEs ONLY for pricebooks where the product already has existing PBEs
    public List<PricebookEntry> createRCAPBEs(List<Product2> products, Map<Id, List<PriceBookEntry>> existingAllPBEs) {
        List<PricebookEntry> rcaPBEs = new List<PricebookEntry>();
        
        System.debug('Creating RCA PBEs for ' + products.size() + ' products');
        
        // FIXED: Bulk query for RCA pricebooks to avoid queries in loop
        Map<Id, Pricebook2> rcaPBMap = new Map<Id, Pricebook2>([SELECT Id, Name FROM Pricebook2 WHERE Id IN :rcaPBIds]);
        
        // FIXED: Bulk query for original pricebooks to avoid queries in loop
        Map<String, Id> originalPBMap = new Map<String, Id>();
        for(Pricebook2 pb : [SELECT Id, Name FROM Pricebook2 WHERE IsActive = true AND Name != 'Standard Price Book' AND (NOT Name LIKE 'RCA_%')]) {
            originalPBMap.put(pb.Name, pb.Id);
        }
        
        // Create a map of RCA pricebook to original pricebook mapping
        Map<Id, Id> rcaToOriginalPBMap = new Map<Id, Id>();
        Map<Id, String> rcaPBNameMap = new Map<Id, String>();
        
        // FIXED: Replace the entire loop that had queries inside with this optimized version
        for(Id rcaPBId : rcaPBIds) {
            if(rcaPBMap.containsKey(rcaPBId)) {
                String rcaPBName = rcaPBMap.get(rcaPBId).Name;
                rcaPBNameMap.put(rcaPBId, rcaPBName);
                String originalPBName = rcaPBName.replace('RCA_', '');
                
                if(originalPBMap.containsKey(originalPBName)) {
                    rcaToOriginalPBMap.put(rcaPBId, originalPBMap.get(originalPBName));
                }
            }
        }
        
        for (Product2 prod : products) {
            List<PricebookEntry> existingPBEs = existingAllPBEs.get(prod.Id);
            
            // Fallback for Bundle products
            if (prod.Type == 'Bundle' && (existingPBEs == null || existingPBEs.isEmpty())) {
                List<Id> allPBIds = new List<Id>{stdPB};
                allPBIds.addAll(customPBIds);
                allPBIds.addAll(rcaPBIds);
                Map<Id, List<PriceBookEntry>> oldPBEMap = getExistingPBEMap(new List<Product2>(), allPBIds, prod.StockKeepingUnit);
                existingPBEs = oldPBEMap.isEmpty() ? null : oldPBEMap.values().get(0);
            }
            
            if (existingPBEs == null || existingPBEs.isEmpty()) {
                System.debug('No existing PBEs found for Product2: ' + prod.Id);
                continue;
            }
            
            // Get the appropriate PSM ID
            String psmKey = getPSMKey(prod);
            Id finalPSMId = psmMap.get(psmKey);
            
            if (finalPSMId == null) {
                System.debug('No PSM found for key: ' + psmKey + ' | Product2: ' + prod.Id);
                continue;
            }
            
            // FIXED: Create a set of pricebook IDs where this product has existing PBEs
            Set<Id> pricebooksWithExistingPBEs = new Set<Id>();
            for (PricebookEntry pbe : existingPBEs) {
                pricebooksWithExistingPBEs.add(pbe.Pricebook2Id);
            }
            
            // Create RCA PBEs ONLY for RCA pricebooks where the original pricebook has existing PBEs
            for (Id rcaPBId : rcaPBIds) {
                Id originalPBId = rcaToOriginalPBMap.get(rcaPBId);
                
                // FIXED: Only proceed if the product has existing PBEs in the original pricebook
                if (originalPBId == null || !pricebooksWithExistingPBEs.contains(originalPBId)) {
                    System.debug('Product ' + prod.Id + ' has no existing PBEs in original pricebook for RCA: ' + rcaPBNameMap.get(rcaPBId));
                    continue;
                }
                
                System.debug('Processing RCA Pricebook: ' + rcaPBNameMap.get(rcaPBId) + ' (' + rcaPBId + ') - Product has existing PBEs in original');
                
                // Check if RCA PBE already exists
                Boolean alreadyExists = false;
                for (PricebookEntry existing : existingPBEs) {
                    if (existing.Pricebook2Id == rcaPBId && existing.ProductSellingModelId == finalPSMId) {
                        System.debug('RCA PBE already exists for Product2: ' + prod.Id + ' in RCA PB: ' + rcaPBId);
                        alreadyExists = true;
                        rcaPBEs.add(existing);
                        break;
                    }
                }
                
                if (!alreadyExists) {
                    // Find the price from the corresponding original pricebook
                    Decimal unitPrice = null;
                    Boolean isActive = true;
                    
                    // Look for price in the original pricebook
                    for (PricebookEntry pbe : existingPBEs) {
                        if (pbe.Pricebook2Id == originalPBId && pbe.ProductSellingModelId == null) {
                            unitPrice = pbe.UnitPrice;
                            isActive = pbe.IsActive;
                            System.debug('Found price from original PB: ' + unitPrice + ' for Product2: ' + prod.Id);
                            break;
                        }
                    }
                    
                    // If no price found in original pricebook, use standard pricebook as fallback
                    if (unitPrice == null) {
                        for (PricebookEntry pbe : existingPBEs) {
                            if (pbe.Pricebook2Id == stdPB && pbe.ProductSellingModelId == null) {
                                unitPrice = pbe.UnitPrice;
                                isActive = pbe.IsActive;
                                System.debug('Found price from standard PB: ' + unitPrice + ' for Product2: ' + prod.Id);
                                break;
                            }
                        }
                    }
                    
                    if (unitPrice != null) {
                        PricebookEntry newRCAPBE = new PricebookEntry(
                            Product2Id = prod.Id,
                            Pricebook2Id = rcaPBId,
                            ProductSellingModelId = finalPSMId,
                            UnitPrice = unitPrice,
                            IsActive = isActive,
                            Is_RCA_Entry__c = true
                        );
                        rcaPBEs.add(newRCAPBE);
                        System.debug('Created new RCA PBE for Product2: ' + prod.Id + ' in RCA PB: ' + rcaPBId);
                    } else {
                        System.debug('No price found for Product2: ' + prod.Id + ' in RCA PB: ' + rcaPBId);
                    }
                }
            }
        }
        
        System.debug('Total RCA PBEs created/returned: ' + rcaPBEs.size());
        return rcaPBEs;
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
            if(option == 'insert') {
                Database.SaveResult[] results = Database.insert(dmlList, false);
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
            } else {
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
            }
        } catch (Exception e) {
            RCA_BatchExceptionLogger.logExceptions(
                'RCA_Pricebook',
                context,
                'DML_Exception',
                null,
                e.getMessage()
            );
        }
    }    
}