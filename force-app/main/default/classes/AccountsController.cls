public without sharing class AccountsController {
    
    @AuraEnabled(cacheable=true)
    public static List<Account> getAccounts(){
        try {

            List<Account> accList = [Select Id, Name, (Select Id, AccountId, lastName, Phone, Email from Contacts) from account];
            System.debug('accList -->>'+accList);
            return accList;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}