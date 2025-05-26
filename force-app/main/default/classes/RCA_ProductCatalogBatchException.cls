public class RCA_ProductCatalogBatchException {
    public static String logException(String className, String context, String recordIdentifier, Database.Error error) {
        String errorMsg = '[Class: ' + className + '] '
                        + '[Context: ' + context + '] '
                        + '[Record: ' + recordIdentifier + '] '
                        + '[Message: ' + error.getMessage();

        if (error.getStatusCode() != null) {
            errorMsg += ', StatusCode: ' + error.getStatusCode();
        }

        if (error.getFields() != null && !error.getFields().isEmpty()) {
            errorMsg += ', Fields: ' + String.join(error.getFields(), ',');
        }

        errorMsg += ']';

        System.debug(LoggingLevel.ERROR, errorMsg); 

        return errorMsg; 
    }
}
