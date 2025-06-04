// Use .apex files to store anonymous Apex.
// You can execute anonymous Apex in VS Code by selecting the
//     apex text and running the command:
//     SFDX: Execute Anonymous Apex with Currently Selected Text
// You can also execute the entire file by running the command:
//     SFDX: Execute Anonymous Apex with Editor Contents

Map<String, Schema.SObjectField> fieldsMap = Schema.SObjectType.SBQQ__ProductOption__c.fields.getMap();
for (SBQQ__ConfigurationAttribute__c attr : [SELECT Id, Name, SBQQ__Product__c, SBQQ__Product__r.StockKeepingUnit,
SBQQ__Required__c, SBQQ__TargetField__c
FROM SBQQ__ConfigurationAttribute__c
WHERE SBQQ__Product__c = '01tKj00000QXM0FIAX']) {
    String targetFieldApiName = attr.SBQQ__TargetField__c;

    if (fieldsMap.containsKey(targetFieldApiName)) {
        Schema.DescribeFieldResult fieldDescribe = fieldsMap.get(targetFieldApiName).getDescribe();
        System.debug('Data type of ' + targetFieldApiName + ' is: ' + fieldDescribe.getType());
    }
}
