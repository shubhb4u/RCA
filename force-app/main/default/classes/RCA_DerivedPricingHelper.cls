public class RCA_DerivedPricingHelper {
    
    public List<PricebookEntry> newBundlePBEs = new List<PricebookEntry>();
    public List<PricebookEntry> newRCABundlePBEs = new List<PricebookEntry>();
    public List<PricebookEntry> useExistingRCABundlePBEs = new List<PricebookEntry>();
    public List<PricebookEntry> sourceRCABundlePBEs = new List<PricebookEntry>();
    //  public List<String> errorMessages;
    
    private Id standardPricebook2Id;
    private Id rcaPricebook2Id;
    private Id oneTimeProductSellingModelId;
    public Map<Id, Decimal> productIdToPercentMap = new Map<Id, Decimal>();
    public Map<Id, Product2> productIdToSubscriptionBaseMap = new Map<Id, Product2>();
    public List<PriceBookEntryDerivedPrice> newDerivedPrices = new List<PriceBookEntryDerivedPrice>();
    Map<Id, List<PricebookEntry>> standardExistingPBEKeys = new Map<Id, List<PricebookEntry>>();
    Map<Id, List<PricebookEntry>> rcaExistingPBEKeys = new Map<Id, List<PricebookEntry>>();
    
    
    public RCA_DerivedPricingHelper() {
        
        
        try {
            Map<String, Id> pricebookMap = new Map<String, Id>();
            for (Pricebook2 pb : [SELECT Id, Name FROM Pricebook2 WHERE Name IN ('Standard Price Book', 'RCA_PriceBook')]) {
                pricebookMap.put(pb.Name, pb.Id);
            }
            
            standardPricebook2Id = pricebookMap.get('Standard Price Book');
            rcaPricebook2Id = pricebookMap.get('RCA_PriceBook');
            
            oneTimeProductSellingModelId = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time' LIMIT 1].Id;
        } 
        catch (Exception e) {
            //errorMessages.add('Error initializing helper: ' + e.getMessage());
            RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'RCA_DerivedPricingHelper', 'Pricebook2', new List<Database.error>(), 'Error initializing helper: ' + e.getMessage());
        }
        finally{
            RCA_BatchExceptionLogger.flushLogs();
        }
    }
    
    public void processProducts(List<Product2> potProducts) {
        System.debug('### Starting processProducts with ' + potProducts.size() + ' products');
        collectPOTData(potProducts);
        insertNewPBEs(potProducts);
        createDerivedPricesForNewPBEs();
        insertDerivedPrices();
    }
    
    public void collectPOTData(List<Product2> potProducts) {
        for (Product2 p : potProducts) {
            productIdToPercentMap.put(p.Id, p.SBQQ__SubscriptionPercent__c);
            productIdToSubscriptionBaseMap.put(p.Id, p);
        }
    }
    
    
    public void insertNewPBEs(List<Product2> potProducts) {
        
        // Step 1: Collect existing PBEs
        for (PricebookEntry pb : [
            SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, UnitPrice, IsDerived
            FROM PricebookEntry
            WHERE Product2Id IN :potProducts]) {
                
                if(pb.Pricebook2Id == standardPricebook2Id){
                    if(!standardExistingPBEKeys.containsKey(pb.Product2Id)){
                        standardExistingPBEKeys.put(pb.Product2Id,new List<PricebookEntry>{} );
                    }
                    standardExistingPBEKeys.get(pb.Product2Id).add(pb);
                }
                
                if(pb.Pricebook2Id == rcaPricebook2Id){
                    if(!rcaExistingPBEKeys.containsKey(pb.Product2Id)){
                        rcaExistingPBEKeys.put(pb.Product2Id,new List<PricebookEntry>{} );
                    }
                    rcaExistingPBEKeys.get(pb.Product2Id).add(pb);
                }
                
            }
        
        // Step 2: Loop through each product
        for (Product2 bundle : potProducts) {
            Boolean hasStandard = standardExistingPBEKeys.containsKey(bundle.Id);
            Boolean hasRCA = rcaExistingPBEKeys.containsKey(bundle.Id);
            
            // Case 1: Has Standard but not RCA
            if (hasStandard && !hasRCA) {
                Boolean matchFound = false;
                
                for (PricebookEntry pb : standardExistingPBEKeys.get(bundle.Id)) {
                    if (pb.IsDerived && pb.UnitPrice == 0 && pb.ProductSellingModelId == getProductSellingModelId()) {
                        newRCABundlePBEs.add(clonePBE(bundle.Id, pb.ProductSellingModelId, rcaPricebook2Id));
                        matchFound = true;
                        break; // Perfect match found, skip rest
                    }
                }
                
                if (!matchFound) {
                    Id finalPSMO = getPSMOOrDefault(bundle.Id);
                    newBundlePBEs.add(clonePBE(bundle.Id, finalPSMO, standardPricebook2Id));
                    newRCABundlePBEs.add(clonePBE(bundle.Id, finalPSMO, rcaPricebook2Id));
                }
            }
            
            
            // Case 2: Has neither Standard nor RCA
            else if (!hasStandard && !hasRCA) {
                Id finalPSMO = getPSMOOrDefault(bundle.Id);
                newBundlePBEs.add(clonePBE(bundle.Id, finalPSMO, standardPricebook2Id));
                newRCABundlePBEs.add(clonePBE(bundle.Id, finalPSMO, rcaPricebook2Id));
            }
            
            // Case 3: Has RCA (check if it's not derived or unit price is non-zero)
            else if (hasRCA) {
                
                Boolean newMatchFound = false;
                for (PricebookEntry pb : rcaExistingPBEKeys.get(bundle.Id)) {
                    if (pb.IsDerived && pb.UnitPrice == 0 && pb.ProductSellingModelId == getProductSellingModelId()) {
                        newMatchFound = true;
                        useExistingRCABundlePBEs.add(pb);
                        break;
                    }
                }
                
                if(!newMatchFound){
                    Id finalPSMO = getPSMOOrDefault(bundle.Id);
                    newBundlePBEs.add(clonePBE(bundle.Id, finalPSMO, standardPricebook2Id));
                    newRCABundlePBEs.add(clonePBE(bundle.Id, finalPSMO, rcaPricebook2Id));
                }
            }
        }
        
        // Step 3: Insert PBEs and collect errors
        insertPBEs(newBundlePBEs, 'standard');
        insertPBEs(newRCABundlePBEs, 'RCA');
    }
    
    private void insertPBEs(List<PricebookEntry> pbes, String label) {
        if (pbes.isEmpty()) return;
        
        try {
            Database.SaveResult[] results = Database.insert(pbes, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    //errorMessages.add('Failed to insert ' + label + ' PBE: ' + results[i].getErrors()[0].getMessage());
                    String debuginfo = JSON.Serialize(results[i]);
                    RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'insertPBEs', 'DerivedPrice', results[i].getErrors(),debuginfo);
                } else {
                    PricebookEntry insertedPBE = pbes[i];
                    insertedPBE.Id = results[i].getId();
                    
                    if (label == 'RCA') {
                        newRCABundlePBEs[i].Id = results[i].getId();
                        
                        // ✅ Add to RCA Map
                        if (!rcaExistingPBEKeys.containsKey(insertedPBE.Product2Id)) {
                            rcaExistingPBEKeys.put(insertedPBE.Product2Id, new List<PricebookEntry>());
                        }
                        rcaExistingPBEKeys.get(insertedPBE.Product2Id).add(insertedPBE);
                        
                    } else if (label == 'standard') {
                        // ✅ Add to Standard Map
                        if (!standardExistingPBEKeys.containsKey(insertedPBE.Product2Id)) {
                            standardExistingPBEKeys.put(insertedPBE.Product2Id, new List<PricebookEntry>());
                        }
                        standardExistingPBEKeys.get(insertedPBE.Product2Id).add(insertedPBE);
                    }
                }
            }
        } catch (Exception e) {
            //errorMessages.add('Error inserting ' + label + ' PBEs: ' + e.getMessage());
            RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'insertPBEs','DerivedPrice',  new List<Database.Error>() ,'Exception: ' + e.getMessage());
        }
        finally{
            RCA_BatchExceptionLogger.flushLogs();
        }
    }
    
    
    public void createDerivedPricesForNewPBEs() {
        
        if(!useExistingRCABundlePBEs.isEmpty()) newRCABundlePBEs.addAll(useExistingRCABundlePBEs);
        
        //Step 1: Query existing derived prices to avoid duplicates
        Set<Id> rcaPBEIds = new Set<Id>();
        for (PricebookEntry entry : newRCABundlePBEs) {
            if (entry.Id != null) {
                rcaPBEIds.add(entry.Id);
            }
        }
        
        Map<Id, PriceBookEntryDerivedPrice> existingDerivedPriceMap = new Map<Id, PriceBookEntryDerivedPrice>();
        if (!rcaPBEIds.isEmpty()) {
            for (PriceBookEntryDerivedPrice existing : [
                SELECT Id, PricebookEntryId 
                FROM PriceBookEntryDerivedPrice 
                WHERE PricebookEntryId IN :rcaPBEIds
            ]) {
                existingDerivedPriceMap.put(existing.PricebookEntryId, existing);
            }
        }
        
        for (PricebookEntry entry : newRCABundlePBEs) {
            
            if (existingDerivedPriceMap.containsKey(entry.Id)) {
                // Skip if already exists
                continue;
            }
            
            Decimal percent = productIdToPercentMap.get(entry.Product2Id);
            Product2 product = productIdToSubscriptionBaseMap.get(entry.Product2Id);
            
            if (percent == null || product == null || product.SBQQ__SubscriptionBase__c == null) {
                // errorMessages.add('Missing subscription data for product: ' + entry.Product2Id);
                String debuginfo = JSON.serialize(product)+ ' |  Percent of Total : '+percent +' |  Product : '+product + '  |  SBQQ__SubbscriptionBase__c : '+ product.SBQQ__SubscriptionBase__c;
                 RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'createDerivedPricesForNewPBEs', 'DerivedPrice',  new List<Database.Error>(),debuginfo);
				 RCA_BatchExceptionLogger.flushLogs();
                continue;
            }
            
            String formula = '';
            String source = '';
            
            if (product.SBQQ__SubscriptionBase__c == 'Net') {
                source = 'Header';
                formula = 'HeaderTotal * ' + String.valueOf(percent / 100);
            } else if (product.SBQQ__SubscriptionBase__c == 'List') {
                source = 'Product';
                formula = 'ListPrice * ' + String.valueOf(percent / 100);
            }
            
            
            PriceBookEntryDerivedPrice dp = new PriceBookEntryDerivedPrice(
                DerivedPricingScope = 'Transactional',
                PricingSource = source,
                PricebookEntryId = entry.Id,
                PricebookId = entry.Pricebook2Id,
                Formula = formula,
                EffectiveFrom = Date.today()
            );
            
            if (source == 'Product') {
                getSourceProductPriceBook(product.SBQQ__SubscriptionTarget__c); // Create same PriceBook for Source product also
                insertPBEs(sourceRCABundlePBEs, 'Source RCA');
                dp.ContributingProductId = product.SBQQ__SubscriptionTarget__c;
            }
            
            newDerivedPrices.add(dp);
        }
    }
    
    // this block will insert the record in derivedPrice object
    private void insertDerivedPrices() {
        if (!newDerivedPrices.isEmpty()) {
            try {
                Database.SaveResult[] results = Database.insert(newDerivedPrices, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (!results[i].isSuccess()) {
                        //errorMessages.add('DerivedPrice insert failed: ' + results[i].getErrors()[0].getMessage());
                        RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'insertDerivedPrices', 'DerivedPrice',results[i].getErrors() ,'DerivedPrice insert failed: ' + results[i].getErrors()[0].getMessage());
                        
                    }
                }
            } catch (Exception e) {
                // errorMessages.add('Exception inserting derived prices: ' + e.getMessage());
                RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'insertDerivedPrices', 'DerivedPrice',  new List<Database.Error>(),'Exception inserting derived prices: ' + e.getMessage());
            }
            finally{
                RCA_BatchExceptionLogger.flushLogs();
            }
        }
    }
    
    private Id getPSMOOrDefault(Id productId) {
        String psmoId = createPSMO(productId);
        return psmoId != null ? psmoId : oneTimeProductSellingModelId; // Remove this reference
    }
    
    private void getSourceProductPriceBook(Id productId){
        
        List<PriceBookEntry> pbList = [SELECT Id, Product2Id FROM PricebookEntry WHERE Pricebook2Id = :rcaPricebook2Id 
                                       AND Product2Id = :productId];
        
        if(pbList.isEmpty()){
            List<PriceBookEntry> stdPbList = [SELECT Id, Product2Id, UnitPrice, ProductSellingModelId 
                                              FROM PricebookEntry 
                                              WHERE Pricebook2Id = :standardPricebook2Id 
                                              AND Product2Id = :productId];
            
            Id finalPSMO = getPSMOOrDefault(productId);
            sourceRCABundlePBEs.add(clonesourcePBE(productId,finalPSMO,rcaPricebook2Id, stdPbList));
            
        }
    }
    
    private PricebookEntry clonePBE(Id productId, Id psmoId, Id pricebookId) {
        
        return new PricebookEntry(
            IsActive = true,	
            IsDerived = true,
            UnitPrice = 0,
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            ProductSellingModelId = psmoId
        );
        
    }
    
    private PricebookEntry cloneSourcePBE(Id productId, Id psmoId, Id pricebookId, List<PricebookEntry> stdPBList) {
        return new PricebookEntry(
            IsActive = true,
            IsDerived = false,
            UnitPrice = stdPBList[0].unitPrice,
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            ProductSellingModelId = psmoId
        );
    }
    
    
    private Id createPSMO(Id productId) {
        try {
            // Check if One Time PSMO already exists for the product
            List<ProductSellingModelOption> existingPSMOs = [
                SELECT ProductSellingModelId 
                FROM ProductSellingModelOption 
                WHERE Product2Id = :productId 
                AND ProductSellingModel.Name = 'One Time'
                LIMIT 1
            ];
            
            if (!existingPSMOs.isEmpty()) {
                return existingPSMOs[0].ProductSellingModelId;
            }
            
            // Else, create new One Time PSMO
            Id psmId = [SELECT Id FROM ProductSellingModel WHERE Name = 'One Time' LIMIT 1].Id;
            
            ProductSellingModelOption newPSMO = new ProductSellingModelOption(
                Product2Id = productId,
                ProductSellingModelId = psmId
            );
            //insert newPSMO;
            try {
                Database.SaveResult sv = Database.insert(newPSMO, false);
                
                if (sv.isSuccess()) {
                    // Success: do nothing
                } else {
                    RCA_BatchExceptionLogger.logExceptions(
                        'RCA_DerivedPricingHelper',
                        'createPSMO',
                        'ProductSellingModelOption',
                        sv.getErrors(),
                        'Product2Id: ' + productId
                    );
                }
            } catch (Exception e) {
                RCA_BatchExceptionLogger.logExceptions(
                    'RCA_DerivedPricingHelper',
                    'createPSMO',
                    'ProductSellingModelOption',
                    new List<Database.Error>(), // Empty error list for generic exception
                    'Unexpected error during insert: ' + e.getMessage()
                );
            } finally {
                RCA_BatchExceptionLogger.flushLogs();
            }
            
            return newPSMO.ProductSellingModelId;
            
        } catch (Exception e) {
            //errorMessages.add('Error creating or fetching PSMO for Product2Id ' + productId + ': ' + e.getMessage());
            RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper','createPSMO', 'ProductSellingModelOption',  new List<Database.Error>(),'Error creating or fetching PSMO for Product2Id ' + productId + ': ' + e.getMessage());
            return null;
        }
        finally{
            RCA_BatchExceptionLogger.flushLogs();
        }
    }
    
    private Id getProductSellingModelId() {
        return oneTimeProductSellingModelId;
    }
    
    
}