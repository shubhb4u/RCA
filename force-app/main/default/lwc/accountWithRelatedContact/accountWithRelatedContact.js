import { LightningElement, wire } from 'lwc';
import accountRecords from '@salesforce/apex/AccountsController.getAccounts';

export default class AccountWithRelatedContact extends LightningElement {

    allData = [];
    accounts = [];
    contacts = [];
    value = '';
    displayModal = false;
    conRecordId = null;

    columns = [
        {
            label: 'Account Name',
            fieldName: 'accountId',
            type: 'url',
            typeAttributes: { label: { fieldName: 'accountName' }, target: '_blank' }
        },
        {
            label: 'Contact Name',
            fieldName: 'contactId',
            type: 'url',
            typeAttributes: { label: { fieldName: 'contactName' }, target: '_blank' }
        },
        {
            label: 'Phone',
            fieldName: 'phone',
            type: 'phone'
        },
        {
            label: 'Email',
            fieldName: 'email',
            type: 'email'
        }
    ];

    actions = [
        { label: 'Edit', name: 'Edit' },
        { label: 'Delete', name: 'Delete' }
    ];


    @wire(accountRecords)
    wiredAccounts({ data, error }) {
        if (data) {
            console.log('data -->> ', JSON.stringify(data));
            this.allData = data;
            this.accounts = data.map(account => ({
                label: account.Name,
                value: account.Name
            }));
            console.log('accounts -->> ', JSON.stringify(this.accounts));

        } else if (error) {
            console.log('Error -->> ', error);
        }
    }

    get accountName() {
        return (this.value !== '') ? true : false;
    }

    handleChange(event) {
        this.value = event.detail.value;
        console.log('value -->> ', this.value);
        if (this.value) {
            this.contacts = this.getContacts(this.value);
        }
    }

    getContacts(accName) {

        let flatContacts = [];
        let accountContacts = this.allData.find(acc => acc.Name === accName);

        if (accountContacts.Contacts && accountContacts.Contacts.length > 0) {
            accountContacts.Contacts.forEach(con => {
                flatContacts.push(
                    {
                        accountName: accountContacts.Name,
                        accountId: '/' + con.AccountId,
                        contactName: con.LastName,
                        contactId: '/' + con.Id,
                        phone: con.Phone,
                        email: con.Email
                    });
            });
        }
        console.log('flatContacts -->> ' + JSON.stringify(flatContacts));
        return flatContacts;
    }

    handleRowAction(event) {
        const action = event.detail.action;
        const row = event.detail.row;
        switch (action.name) {
            case 'Edit':
                this.editContactRecord(row);
                break;
            case 'Delete':
                break;
        }
    }

    editContactRecord(row){
        this.displayModal = true;
        this.conRecordId = row.Id;
    }

    closeModalHandler(){
        this.displayModal = false;
    }
}