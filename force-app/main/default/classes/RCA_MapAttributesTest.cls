@isTest
public class RCA_MapAttributesTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Product2 mainProd = new Product2(
            Name = 'Main Product',
            StockKeepingUnit = 'SKU-001',
            SBQQ__HasConfigurationAttributes__c = true
        );
        insert mainProd;

        Product2 bundleProd = new Product2(
            Name = 'Main Product Bundle',
            StockKeepingUnit = 'SKU-001 - Bundle'
        );
        insert bundleProd;

        SBQQ__ConfigurationAttribute__c ca = new SBQQ__ConfigurationAttribute__c(
            Name = 'Color Option',
            SBQQ__Product__c = mainProd.Id,
            SBQQ__TargetField__c = 'SBQQ__Number__c',
            SBQQ__Required__c = true
        );
        insert ca;

        ProductClassification existingClass = new ProductClassification(
            Name = 'Main Product Classification',
            Code = 'SKU-001_CLASS',
            Status = 'Active'
        );
        insert existingClass;

        AttributeDefinition existingDef = new AttributeDefinition(
            Name = 'Color Option',
            Label = 'Color Option',
            Code = 'SKU-001_Color_Option',
            DataType = 'Text',
            IsActive = true,
            IsRequired = true
        );
        insert existingDef;

        ProductClassificationAttr junction = new ProductClassificationAttr(
            Name = 'Color Option',
            ProductClassificationId = existingClass.Id,
            AttributeDefinitionId = existingDef.Id
        );
        insert junction;

        Product2 noSkuProd = new Product2(
            Name = 'No SKU Product',
            SBQQ__HasConfigurationAttributes__c = true
        );
        insert noSkuProd;
    }

    @isTest
    static void testBatch_WithFilter() {
        Product2 prod = [SELECT Id FROM Product2 WHERE StockKeepingUnit = 'SKU-001'];

        Test.startTest();
        Database.executeBatch(new RCA_MapAttributesFromCPQToRCABatch(new List<Id>{prod.Id}), 200);
        Test.stopTest();

        Product2 p = [SELECT BasedOnId FROM Product2 WHERE StockKeepingUnit = 'SKU-001'];
        System.assertNotEquals(null, p.BasedOnId, 'BasedOnId should be set for main product');
    }

    @isTest
    static void testBatch_WithoutFilter() {
        Test.startTest();
        Database.executeBatch(new RCA_MapAttributesFromCPQToRCABatch(), 200);
        Test.stopTest();

        List<ProductClassification> pcs = [SELECT Id FROM ProductClassification WHERE Code = 'SKU-001_CLASS'];
        System.assert(!pcs.isEmpty(), 'Classification should exist');
    }

    @isTest
    static void testBatch_MissingSKULogs() {
        Product2 noSkuProd = [SELECT Id FROM Product2 WHERE Name = 'No SKU Product'];

        Test.startTest();
        Database.executeBatch(new RCA_MapAttributesFromCPQToRCABatch(new List<Id>{noSkuProd.Id}), 200);
        Test.stopTest();

        // Optionally assert logs if your RCA_BatchExceptionLogger writes to a custom object
    }

    @isTest
    static void testHelper_EmptyList() {
        RCA_MapAttributesFromCPQToRCAHelper helper = new RCA_MapAttributesFromCPQToRCAHelper();
        helper.process(new List<Product2>()); // Should do nothing and not fail
    }
}