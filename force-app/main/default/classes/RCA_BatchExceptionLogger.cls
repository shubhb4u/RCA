public class RCA_BatchExceptionLogger {

    public static void logException(String className,  String operation,
        String recordIdentifier, Exception e ) {
        
            String errorDetail = 
            'Class: ' + className + '\n' +
            'Operation: ' + operation + '\n' +
            'Record Identifier: ' + recordIdentifier + '\n' +
            'Exception: ' + e.getMessage();

        System.debug(LoggingLevel.ERROR, errorDetail);
    }
}
