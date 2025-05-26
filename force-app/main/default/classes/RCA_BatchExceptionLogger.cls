public class RCA_BatchExceptionLogger {
    public static String logException(String className, String context, String recordIdentifier, Database.Error error) {
        String errorMsg = '\n[Class: ' + className + ']'
                        + '\n[Context: ' + context + ']'
                        + '\n[Parent Product Record ID: ' + recordIdentifier + ']'
                        + '\n[Message: ' + error.getMessage();

        if (error.getStatusCode() != null) {
            errorMsg += '\n[StatusCode: ' + error.getStatusCode() + ']';
        }

        if (error.getFields() != null && !error.getFields().isEmpty()) {
            errorMsg += '\n[Fields: ' + String.join(error.getFields(), ',') + ']';
        }

        System.debug(LoggingLevel.ERROR, errorMsg);
        return errorMsg;
    }
}
