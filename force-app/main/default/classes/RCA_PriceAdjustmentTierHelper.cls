public class RCA_PriceAdjustmentTierHelper {
    
    public static String getScheduleTypeValue() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return (config != null) ? config.Schedule_Type__c : null;
    }
    
    public static String getTierPercentage() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return (config != null) ? config.TierType__c : null;
    }
     public static String pricebookid(){
         Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return (config != null) ? config.RCA_PricebookId__c : null;
    }
    public static String getTierAmount() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return (config != null) ? config.TierType1__c : null;
    }
    
    public static String TierOverride() {
        Pricing_Method_Config__mdt config = Pricing_Method_Config__mdt.getInstance('PercentOfTotal');
        return (config != null) ? config.TierType2__c : null;
    }

  public static void ProcessPriceAdjustmentSchedule(List<SBQQ__DiscountSchedule__c> cpqDiscountSchedules) {
    List<PriceAdjustmentSchedule> priceAdjustmentSchedulesToBeMigrated = new List<PriceAdjustmentSchedule>();

    List<PriceAdjustmentSchedule> ExistingPriceAdjustmentSchedules = [
        SELECT Id, Name, AdjustmentMethod, ScheduleType
        FROM PriceAdjustmentSchedule
    ];

    Set<String> adjustmentMethodNames = new Set<String>();
    for (PriceAdjustmentSchedule adjustments : ExistingPriceAdjustmentSchedules) {
        adjustmentMethodNames.add(adjustments.AdjustmentMethod);
    }

    for (SBQQ__DiscountSchedule__c schedule : cpqDiscountSchedules) {
        PriceAdjustmentSchedule newSchedule = new PriceAdjustmentSchedule();
        newSchedule.Name = 'Standard ' + schedule.Name;
        newSchedule.AdjustmentMethod = schedule.SBQQ__Type__c;
        newSchedule.Pricebook2Id = pricebookid();
        newSchedule.EffectiveFrom = Date.Today();
        newSchedule.IsActive = false;

        if (adjustmentMethodNames.contains(newSchedule.AdjustmentMethod)) {
            schedule.IsMigrated__c	 = true;
            continue;
        } else {
            priceAdjustmentSchedulesToBeMigrated.add(newSchedule);
            schedule.IsMigrated__c	 = true;
        }
    }

    try {
        Database.SaveResult[] scheduleInsertResults = Database.insert(priceAdjustmentSchedulesToBeMigrated, false);
        for (Integer i = 0; i < scheduleInsertResults.size(); i++) {
            System.debug(scheduleInsertResults[i]);
            if (!scheduleInsertResults[i].isSuccess()) {
                RCA_BatchExceptionLogger.logExceptions(
                    'RCA_PriceAdjustmentTierHelper',
                    'Insert: PriceAdjustmentSchedules',
                    'PriceAdjustmentSchedule',
                    null,
                    'Failed to insert schedule: ' + scheduleInsertResults[i].getErrors()[0].getMessage()
                );
            }
        }
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Insert Catch: PriceAdjustmentSchedules',
            'PriceAdjustmentSchedule',
            null,
            'Unexpected error inserting schedules. Error: ' + e.getMessage()
        );
    }
system.debug('cpqDiscountSchedules><>'+cpqDiscountSchedules);
    try {
        update cpqDiscountSchedules;
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Update: cpqDiscountSchedules',
            'SBQQ__DiscountSchedule__c',
            null,
            'Failed to update CPQ Discount Schedules (IsMigrated__c). Error: ' + e.getMessage()
        );
    }

    List<PriceAdjustmentSchedule> freshlyInsertedSchedules = [
        SELECT Id, Name, AdjustmentMethod, ScheduleType
        FROM PriceAdjustmentSchedule
        WHERE ScheduleType = 'Volume'
    ];

    for (PriceAdjustmentSchedule temp : freshlyInsertedSchedules) {
        temp.IsActive = false;
    }

    try {
        update freshlyInsertedSchedules;
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Update: freshlyInsertedSchedules (IsActive=false)',
            'PriceAdjustmentSchedule',
            null,
            'Failed to deactivate inserted PriceAdjustmentSchedules. Error: ' + e.getMessage()
        );
    }

    Map<String, Id> AdjustmentMethodToIdMap = new Map<String, Id>();
    for (PriceAdjustmentSchedule schedules : freshlyInsertedSchedules) {
        AdjustmentMethodToIdMap.put(schedules.AdjustmentMethod, schedules.Id);
    }

    List<PriceAdjustmentTier> AdjustmentTiersToBeInserted = new List<PriceAdjustmentTier>();

    List<SBQQ__DiscountTier__c> cpqTiers = [
        SELECT Name, SBQQ__LowerBound__c, SBQQ__UpperBound__c, SBQQ__Discount__c,
        SBQQ__DiscountAmount__c, SBQQ__Price__c, SBQQ__Schedule__r.SBQQ__Type__c,
        SBQQ__Schedule__r.SBQQ__Product__c, SBQQ__Schedule__r.SBQQ__Product__r.StockKeepingUnit
        FROM SBQQ__DiscountTier__c
        WHERE IsMigrated__c	 = false
    ];

    List<Id> productIds = new List<Id>();
    List<String> oldProductsSku = new List<String>();

    for (SBQQ__DiscountTier__c disc : cpqTiers) {
        oldProductsSku.add(disc.SBQQ__Schedule__r.SBQQ__Product__r.StockKeepingUnit + ' - Bundle');
    }

    for (SBQQ__DiscountTier__c disc : cpqTiers) {
        productIds.add(disc.SBQQ__Schedule__r.SBQQ__Product__c);
    }

    Map<String, Id> newProductsSkuToId = new Map<String, Id>();
    for (Product2 prod : [SELECT Id, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :oldProductsSku]) {
        newProductsSkuToId.put(prod.StockKeepingUnit.replace(' - Bundle', ''), prod.Id);
        productIds.add(prod.Id);
    }

    List<ProductSellingModelOption> psmoIdList = [
        SELECT Product2Id, ProductSellingModelId
        FROM ProductSellingModelOption
        WHERE Product2Id IN :productIds
    ];

    for (ProductSellingModelOption psmo : psmoIdList) {
        if (!newProductsSkuToId.containsKey(psmo.Product2Id)) {
            newProductsSkuToId.put(psmo.Product2Id, psmo.ProductSellingModelId);
        }
    }

    for (SBQQ__DiscountTier__c tier : cpqTiers) {
        PriceAdjustmentTier newTier = new PriceAdjustmentTier();
        newTier.LowerBound = tier.SBQQ__LowerBound__c;
        newTier.UpperBound = tier.SBQQ__UpperBound__c - 1;

        if (tier.SBQQ__DiscountAmount__c == null && tier.SBQQ__Price__c == null) {
            newTier.TierType = getTierPercentage();
            newTier.TierValue = tier.SBQQ__Discount__c;
        } else if (tier.SBQQ__Discount__c == null && tier.SBQQ__Price__c == null) {
            newTier.TierType = getTierAmount();
            newTier.TierValue = tier.SBQQ__DiscountAmount__c;
        } else {
            newTier.TierType = TierOverride();
            newTier.TierValue = tier.SBQQ__Price__c;
        }

        newTier.EffectiveFrom = Date.today().addDays(1);
        String sku = tier.SBQQ__Schedule__r.SBQQ__Product__r.StockKeepingUnit;
        newTier.Product2Id = newProductsSkuToId.containsKey(sku) ? newProductsSkuToId.get(sku) : tier.SBQQ__Schedule__r.SBQQ__Product__c;
        newTier.ProductSellingModelId = newProductsSkuToId.get(newTier.Product2Id);
        newTier.PriceAdjustmentScheduleId = AdjustmentMethodToIdMap.get(tier.SBQQ__Schedule__r.SBQQ__Type__c);

        AdjustmentTiersToBeInserted.add(newTier);
        tier.IsMigrated__c	 = true;
    }

    try {
        Database.SaveResult[] tierInsertResults = Database.insert(AdjustmentTiersToBeInserted, false);
        for (Integer i = 0; i < tierInsertResults.size(); i++) {
            if (!tierInsertResults[i].isSuccess()) {
                RCA_BatchExceptionLogger.logExceptions(
                    'RCA_PriceAdjustmentTierHelper',
                    'Insert: PriceAdjustmentTiers',
                    'PriceAdjustmentTier',
                    null,
                    'Failed to insert tier: ' + tierInsertResults[i].getErrors()[0].getMessage()
                );
            }
        }
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Insert Catch: PriceAdjustmentTiers',
            'PriceAdjustmentTier',
            null,
            'Unexpected error inserting tiers. Error: ' + e.getMessage()
        );
    }

    try {
        update cpqTiers;
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Update: cpqTiers',
            'SBQQ__DiscountTier__c',
            null,
            'Failed to update Discount Tiers (IsMigrated__c). Error: ' + e.getMessage()
        );
    }

    for (PriceAdjustmentSchedule temp : freshlyInsertedSchedules) {
        temp.IsActive = true;
    }

    try {
        update freshlyInsertedSchedules;
    } catch (Exception e) {
        RCA_BatchExceptionLogger.logExceptions(
            'RCA_PriceAdjustmentTierHelper',
            'Update: freshlyInsertedSchedules (IsActive=true)',
            'PriceAdjustmentSchedule',
            null,
            'Failed to set IsActive=true on PriceAdjustmentSchedules. Error: ' + e.getMessage()
        );
    }
      finally{
          RCA_BatchExceptionLogger.flushLogs();
      }
    // Call flushLogs only once at the end
    
}


    }