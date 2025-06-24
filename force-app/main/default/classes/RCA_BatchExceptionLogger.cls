public class RCA_BatchExceptionLogger {

    @TestVisible
    public static List<String> testErrors = new List<String>();

    public static String logException(String className, String context, String sObjectType, Database.Error error, String CPQErrorRecord) {
        String errorMsg = '\n[Message: ' + error.getMessage()
                        + '\n'
                        + '\n[*** CPQ source record: *** ' + CPQErrorRecord + ']' + '\n';

        if (error.getStatusCode() != null) {
            errorMsg += '\n[StatusCode: ' + error.getStatusCode() + ']' + '\n';
        }

        if (error.getFields() != null && !error.getFields().isEmpty()) {
            errorMsg += '\n[Fields: ' + String.join(error.getFields(), ',') + ']';
            
        }

        // Capture in static list only during test
        if (Test.isRunningTest()) {
            testErrors.add(errorMsg);
        }

        System.debug(LoggingLevel.ERROR, errorMsg);

        try {
            Batch_Error_Log__c log = new Batch_Error_Log__c(
                Batch_Class_Name__c = className,
                Method_Name__c = context,
                Error_Message__c = errorMsg,
                SObject_Type__c = sObjectType
            );
            insert log;
        } catch (Exception e) {
            // You could add fallback debug or monitoring here if logging fails.
            System.debug('Failed to log error: ' + e.getMessage());
        }

        return errorMsg;
    }
}