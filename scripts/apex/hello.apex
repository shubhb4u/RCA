// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

string tempvar = 'Enter_your_name_here';
System.debug('Hello World!');
System.debug('My name is ' + tempvar);

RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{'01tKj00000QXTgTIAX'});
Database.executeBatch(batch);



RCA_MapAttributesFromCPQToRCABatch batch = new RCA_MapAttributesFromCPQToRCABatch(new List<Id>{'01tKj00000QXVuTIAX', '01tKj00000QXWGbIAP'});
Database.executeBatch(batch);

RCA_PricebookBatch batch = new RCA_PricebookBatch(new List<Id>{'01tKj00000QXVfjIAH'});
Database.executeBatch(batch);

RCA_PricebookBatchVersion2 batch = new RCA_PricebookBatchVersion2(new List<Id>{'01tKj00000QXVfjIAH'});
Database.executeBatch(batch);

RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{ '01tKj00000QXYbVIAX'});
Database.executeBatch(batch);

RCA_BundleDerivedPricingBatch batch = new RCA_BundleDerivedPricingBatch(new List<Id>{ '01tKj00000QXYCUIA5'});
Database.executeBatch(batch);

