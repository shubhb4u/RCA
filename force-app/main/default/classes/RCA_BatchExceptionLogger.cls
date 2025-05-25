public class RCA_BatchExceptionLogger {

    // Original method - formats a simple error string
    public static String logException(String className, String errorContext,
                                     String recordIdentifier, Object errorDetail) {
        String message = className + ' | ' + errorContext + ' | ' + 
                         recordIdentifier + ' | ' + errorDetail;
        System.debug('EXCEPTION: ' + message);
        return message;
    }

    // Overloaded method to support record Id + Database.Error
    public static String logException(String className, String errorContext,
                                      Object recordIdentifier, Database.Error errorDetail) {
        String errorMsg = (errorDetail != null) ? errorDetail.getMessage() : 'Unknown Error';
        List<String> errorFields = (errorDetail != null && errorDetail.getFields() != null)
            ? errorDetail.getFields()
            : new List<String>();
        String errorFieldStr = String.join(errorFields, ', ');

        String message = className + ' | ' + errorContext + ' | ' +
                         String.valueOf(recordIdentifier) + ' | ' +
                         errorMsg + ' | Fields: ' + errorFieldStr;

        System.debug('EXCEPTION: ' + message);
        return message;
    }
}
