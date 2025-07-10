public class RCA_DerivedPricingHelper {
    
    @TestVisible private static Boolean forceExceptionInTest = false;
    public  Id stdPB; 
    public  Id rcaPB;
    public  Id proId;
    public  String type = 'Bundle';
    public  Map<String, Id> psmMap = new Map<String, Id>(); 
    Map<Id, Decimal> productIdToPercentMap = new Map<Id, Decimal>();
    public Map<Id, Product2> productIdToSubscriptionBaseMap = new Map<Id, Product2>();
    public List<PriceBookEntryDerivedPrice> newDerivedPrices = new List<PriceBookEntryDerivedPrice>();


    public RCA_DerivedPricingHelper(){

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
    
        // If Standalone products exist - 
        if (!products.isEmpty()) {
            
            //1. Create PSMOs for all products as it is Mandate to create PBE's
            upsertPSMOs(products,  'old');
    
            Map<Id, List<PriceBookEntry>> existingStandardPBEs = getExistingPBEMap(products, new List<Id>{stdPB});
            Map<Id, List<PriceBookEntry>> existingRCAPBEs = getExistingPBEMap(products, new List<Id>{rcaPB});
    
            //If oldProducts have standard PBE, then just create a new RCA PBE - 
            List<PricebookEntry> stdPBEs = clonePBEs(products, stdPB, existingStandardPBEs, null);
            performDML(stdPBEs, 'Upsert: Standard PBEs (Old)', 'upsert');
    
            List<PricebookEntry> rcaPBEs = clonePBEs(products, rcaPB, existingStandardPBEs, existingRCAPBEs);
            performDML(rcaPBEs, 'Upsert: RCA PBEs (Old)', 'upsert');

            for(Product2 pro: products){
                if(!productIdToPercentMap.containsKey(pro.Id)){
                    productIdToPercentMap.put(pro.Id, pro.SBQQ__SubscriptionPercent__c);
                    productIdToSubscriptionBaseMap.put(pro.Id, pro);
                }
            }
            
            createDerivedPricesForNewPBEs(rcaPBEs);

            insertDerivedPrices();
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


    public Map<Id, List<PriceBookEntry>> getExistingPBEMap(List<Product2> products, List<Id> pbIds) {

        String query = 'SELECT Id, Product2Id, Pricebook2Id, ProductSellingModelId, productSellingModel.SellingModelType, UnitPrice, IsActive, isDerived FROM PricebookEntry WHERE Pricebook2Id IN :pbIds AND Product2Id IN : products';
        
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
    
            //1. Standard path: If RCA map is null, check and create standard PBE first and then RCA PBE - 
            if (existingRCAMap == null) {

                List<PricebookEntry> existingPBEs = existingStandardMap.get(prod.Id);
                if (existingPBEs != null) {
                    for (PricebookEntry existing : existingPBEs) {
                        if (existing.Pricebook2Id == pbId && existing.ProductSellingModelId == finalPSMId && existing.isDerived && existing.UnitPrice == 0) {
                            System.debug('Standard PBE already exists for Product2: ' + prod.Id + ', skipping clone.');
                            alreadyExists = true;
                            cloneList.add(existing);
                            break;
                        }
                    }
                }
            } 
            //2. RCA path: check RCA PBEs to avoid duplicates, base price from standard
            else {

                List<PricebookEntry> existingRCAPBEs = existingRCAMap.get(prod.Id);
                if (existingRCAPBEs != null) {
                    for (PricebookEntry existing : existingRCAPBEs) {
                        if (existing.Pricebook2Id == pbId && existing.ProductSellingModelId == finalPSMId && existing.isDerived && existing.UnitPrice == 0) {
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
                    UnitPrice = 0,
                    IsActive = true,
                    IsDerived = true
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
                    String sObjectType = dmlList[i].getSObjectType().getDescribe().getName(); 
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
    
    
    public void createDerivedPricesForNewPBEs(List<PricebookEntry> rcaPBEs) {
        
        if(rcaPBEs == null || rcaPBEs.isEmpty()) return;
        
        //Step 1: Query existing derived prices to avoid duplicates
        Set<Id> rcaPBEIds = new Set<Id>();
        for (PricebookEntry entry : rcaPBEs) {
            if (entry.Id != null) {
                rcaPBEIds.add(entry.Id);
            }
        }
        
        Map<Id, PriceBookEntryDerivedPrice> existingDerivedPriceMap = new Map<Id, PriceBookEntryDerivedPrice>();
        if (!rcaPBEIds.isEmpty()) {
            for (PriceBookEntryDerivedPrice existing : [SELECT Id, PricebookEntryId FROM PriceBookEntryDerivedPrice 
                WHERE PricebookEntryId IN :rcaPBEIds ]) {
                existingDerivedPriceMap.put(existing.PricebookEntryId, existing);
            }
        }
        
        for (PricebookEntry entry : rcaPBEs) {
            
            if (existingDerivedPriceMap.containsKey(entry.Id)) {
                // Skip if already exists
                continue;
            }
            
            Decimal percent = productIdToPercentMap.get(entry.Product2Id);
            Product2 product = productIdToSubscriptionBaseMap.get(entry.Product2Id);
            
            if (percent == null || product == null || product.SBQQ__SubscriptionBase__c == null) {
                // errorMessages.add('Missing subscription data for product: ' + entry.Product2Id);
                String debuginfo = 'Percent of Total : '+percent +' |  Product : '+product + '  |  SBQQ__SubbscriptionBase__c : '+ product.SBQQ__SubscriptionBase__c;

                 RCA_BatchExceptionLogger.logExceptions('RCA_DerivedPricingHelper', 'createDerivedPricesForNewPBEs', 'DerivedPrice',  new List<Database.Error>(), debuginfo);
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

                List<PriceBookEntry> sourcExistingRCAPBE = [Select id  from priceBookEntry where Product2Id =: product.SBQQ__SubscriptionTarget__c and PriceBook2Id =: rcaPB];

                if(sourcExistingRCAPBE == null || sourcExistingRCAPBE.isEmpty()){
                    
                    // Create same PriceBook for Source product also
                    List<Product2> prodList = [SELECT Id, Name, StockKeepingUnit, SBQQ__SubscriptionPercent__c, IsProcessed__c,        SBQQ__SubscriptionBase__c, SBQQ__SubscriptionTarget__c, SBQQ__SubscriptionType__c, SBQQ__SubscriptionPricing__c FROM Product2 where Id =: product.SBQQ__SubscriptionTarget__c];

                    upsertPSMOs(prodList,  'old');

                    Map<Id, List<PriceBookEntry>> existingStandardPBEs = getExistingPBEMap(prodList, new List<Id>{stdPB});
                    Map<Id, List<PriceBookEntry>> existingRCAPBEs = getExistingPBEMap(prodList, new List<Id>{rcaPB});
            
                    //If oldProducts have standard PBE, then just create a new RCA PBE - 
                    List<PricebookEntry> stdSourcePBEs = clonePBEs(prodList, stdPB, existingStandardPBEs, null);
                    performDML(stdSourcePBEs, 'Upsert: Standard Source for derivedPrices PBEs (Old)', 'upsert');
            
                    List<PricebookEntry> rcaSourcePBEs = clonePBEs(prodList, rcaPB, existingStandardPBEs, existingRCAPBEs);
                    performDML(rcaSourcePBEs, 'Upsert: RCA Source for serivedPrices PBEs (Old)', 'upsert');

                }

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
    
}