// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

string tempvar = 'Enter_your_name_here';
System.debug('Hello World!');
System.debug('My name is ' + tempvar);

RCA_ProductCatalogBatch batch = new RCA_ProductCatalogBatch(new List<Id>{'01tKj00000QXEQOIA5'});
Database.executeBatch(batch);



RCA_MapAttributesFromCPQToRCABatch batch = new RCA_MapAttributesFromCPQToRCABatch(new List<Id>{'01tKj00000QXVuTIAX', '01tKj00000QXWGbIAP'});
Database.executeBatch(batch);