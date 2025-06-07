public class RCA_BatchExceptionLogger {

    @TestVisible
    public static List<String> testErrors = new List<String>();

    public static String logException(String className, String context, SObject recordIdentifier, Database.Error error, String CPQErrorRecord) {
        String errorMsg = '\n[Class: ' + className + ']'
                        + '\n'
                        + '\n[Context: ' + context + ']'
                        + '\n'
                        + '\n[*** Failed new Record description:*** \n' + recordIdentifier + ']'
                        + '\n'
                        + '\n[Message: ' + error.getMessage()
                        + '\n'
                        + '\n[*** CPQ source record: *** ' + CPQErrorRecord + ']';

        if (error.getStatusCode() != null) {
            errorMsg += '\n[StatusCode: ' + error.getStatusCode() + ']';
        }

        if (error.getFields() != null && !error.getFields().isEmpty()) {
            errorMsg += '\n[Fields: ' + String.join(error.getFields(), ',') + ']'
            
            + '\n'
            + '\n'
            + '-----------------------------------------------------------------------------------------------------';
        }

        // Capture in static list only during test
        if (Test.isRunningTest()) {
            testErrors.add(errorMsg);
        }

        System.debug(LoggingLevel.ERROR, errorMsg);
        return errorMsg;
    }
}