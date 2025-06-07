import { LightningElement, api } from 'lwc';

export default class EditContactRecord extends LightningElement {

    @api conRecordId;

    handleSuccess(){
        let myCustomEvent = new CustomEvent('closeModal');
        this.dispatchEvent(myCustomEvent);
    }

    closeModal(){
        this.handleSuccess();
    }

}