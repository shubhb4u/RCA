public class RCA_BatchExceptionLogger {

    private static List<Batch_Error_Log__c> logsToInsert = new List<Batch_Error_Log__c>();

    public static void logExceptions(String className, String context, String sObjectType, List<Database.Error> errors, String CPQErrorRecord) {
        
        if (errors == null || errors.isEmpty()) {
            String fallbackMsg =  + CPQErrorRecord ;
            if (Test.isRunningTest()) {
                testErrors.add(fallbackMsg);
            }

            logsToInsert.add(new Batch_Error_Log__c(
                Batch_Class_Name__c = className,
                Method_Name__c = context,
                Error_Message__c = fallbackMsg,
                SObject_Type__c = sObjectType
            ));
            return;
        }

        for (Database.Error error : errors) {
            String errorMsg =  error.getMessage()
                            + '\n' + CPQErrorRecord + '\n';

            if (error.getStatusCode() != null) {
                errorMsg += 'StatusCode: ' + error.getStatusCode() + '\n';
            }
            if (error.getFields() != null && !error.getFields().isEmpty()) {
                errorMsg += 'Fields: ' + String.join(error.getFields(), ',') + '\n';
            }

            if (Test.isRunningTest()) {
                testErrors.add(errorMsg);
            }

            logsToInsert.add(new Batch_Error_Log__c(
                Batch_Class_Name__c = className,
                Method_Name__c = context,
                Error_Message__c = errorMsg,
                SObject_Type__c = sObjectType
            ));
        }
    }

    public static void flushLogs() {
        if (!logsToInsert.isEmpty()) {
            try {
                insert logsToInsert;
                System.debug('### Inserted logs: ' + logsToInsert.size());
            } catch (Exception e) {
                System.debug('Failed to flush error logs: ' + e.getMessage());
            } finally {
                logsToInsert.clear();
            }
        } else {
            System.debug('### No logs to insert.');
        }
    }
    

    @TestVisible
    public static List<String> testErrors = new List<String>();
}
