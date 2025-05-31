public class RCA_BatchExceptionLogger {
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

        System.debug(LoggingLevel.ERROR, errorMsg);
        return errorMsg;
    }
}