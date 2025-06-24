@isTest
public class RCA_QuoteMigrationTest {
    @testsetup
    static void testDatasetup(){
        Id standardPBID = Test.getStandardPricebookId();
        Account acc1 = new Account(
            Name ='ETG digital');
        
        insert acc1;
        
        Contact con = new Contact(
            lastName='Sundar');
        
        insert con;
        
        Opportunity opp = new Opportunity(
            Name = 'washington',
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting'
        );
        insert opp;
        
        SBQQ__Quote__c quote = new SBQQ__Quote__c();
        quote.SBQQ__Account__c= acc1.Id;
        quote.SBQQ__PrimaryContact__c=con.Id;
        quote.SBQQ__Opportunity2__c=opp.Id;
        quote.SBQQ__BillingName__c=acc1.Name;
        quote.SBQQ__ShippingName__c=con.LastName;
        quote.SBQQ__ExpirationDate__c=Date.today().addMonths(2);
        quote.SBQQ__StartDate__c= Date.today();
        quote.SBQQ__Status__c='In Review';
        quote.SBQQ__PricebookId__c=standardPBID;
        insert quote;
    }
    @isTest
    static void TestDataResult(){
        SBQQ__Quote__c oldquote = [select Name,SBQQ__Account__c,SBQQ__PrimaryContact__c,SBQQ__Opportunity2__c from SBQQ__Quote__c where SBQQ__ShippingName__c='Sundar' and  SBQQ__Account__r.Name='ETG digital'];
        Test.startTest();
        RCA_QuoteMigrationBatch batch = new RCA_QuoteMigrationBatch();
        Database.executeBatch(batch,200);
        Test.stopTest();
        String oldName = 'RCA - '+oldquote.Name;
        Quote newQuote = [select QuoteAccountId,ContactId,Name,OpportunityId from Quote where Name =:oldName];
        System.AssertEquals(newQuote.QuoteAccountId,oldquote.SBQQ__Account__c,'Account is mismatched');
        System.AssertEquals(oldName,newQuote.Name,'Quote is not created');
    }
}