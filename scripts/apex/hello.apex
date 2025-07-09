// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

string tempvar = 'Enter_your_name_here';
System.debug('Hello World!');
System.debug('My name is ' + tempvar);

RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{'01tKj00000QXEQOIA5', '01tKj00000QXVftIAH'});
Database.executeBatch(batch);


RCA_MapAttributesFromCPQToRCABatch batch = new RCA_MapAttributesFromCPQToRCABatch(new List<Id>{'01tKj00000QXpBQIA1'});
Database.executeBatch(batch);


RCA_Pricebook batch = new RCA_Pricebook(new List<Id>{'01tKj00000QXdY5IAL'});
Database.executeBatch(batch);


RCA_DerivedPricingBatch batch = new RCA_DerivedPricingBatch(new List<Id>{ '01tKj00000QXbkrIAD'});
Database.executeBatch(batch);



RCA_CostBookBatch batch = new RCA_CostBookBatch(new List<Id>{ '01tKj00000QXQHbIAP'});
Database.executeBatch(batch);

