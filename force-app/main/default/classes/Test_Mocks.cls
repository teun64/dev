/**
 * Edited by Gerbrand Spaans (Gen25) on 26/10/2023.
 * Provides a simplified HttpCalloutMock interface.
 *
 * String body = '{"your":"body"}';
   Test_Mock mock = new Test_Mock(body, 200);
   Test.setMock(HttpCalloutMock.class, mock);
 */
@IsTest
public with sharing class Test_Mocks implements HttpCalloutMock {
    private final Boolean shouldTrowException;
    private final HttpResponse response;

    /**
     * Is called by the SF Test Framework when the Http().send() method is called.
     * @param request The input request. Is passed by the non-test part of your code.
     *
     * @return HttpResponse code set by the constructors
     */
    public HttpResponse respond(HttpRequest request) {
        if(this.shouldTrowException) {
            throw new MOCK_EXCEPTION();
        }
        return this.response;
    }

    /**
     * Set up a Mock Object using a Blob and a status code
     * @param body Blob body (not bloby)
     * @param statusCode Status code to return
     */
    public Test_Mocks(Blob body, Integer statusCode) {
        this();
        this.response.setBodyAsBlob(body);
        this.response.setStatusCode(statusCode);
    }

    /**
     * Set up a Mock Object using a string and a status code
     * @param body String body
     * @param statusCode Status code to return
     */
    public Test_Mocks(String body, Integer statusCode) {
        this();
        this.response.setBody(body);
        this.response.setStatusCode(statusCode);
    }

    /**
     * Use this constructor if you want to have the Mock throw an error that you either handle or not.
     * @param throwException Set to true will let the CalloutMock respond() method throw the custom MOCK_EXCEPTION.
     */
    public Test_Mocks(Boolean throwException) {
        this();
        this.shouldTrowException = true;
    }

    private Test_Mocks() {
        this.response = new HttpResponse();
        this.shouldTrowException = false;
    }

    /**
     * Get a static resource by static resource name. Returns the blob that you can set as response body. Throws a SOQL
     * Exception if the static resource is not found.
     * @param resourceName Name of the Static resource.
     *
     * @return Blob for the found resource.
     */
    public static Blob getResource(String resourceName) {
        return [SELECT Body FROM StaticResource WHERE Name = :resourceName LIMIT 1].Body;
    }

    /**
     * Custom Exception. Can be used to handle the catch(Exception) clauses that you have no examples for.
     */
    public class MOCK_EXCEPTION extends Exception {}


    public class AlarmContactResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setBody('[{"id": 3428,"installationId": 7587,"contactId": 17516,"firstName": "Stefan","insertion": "","surName": "Nicodem","phoneNumber1": "+31615903586","phoneNumber2": "+31627064628","alarmCode": "jessica","alarmCodeHint": "","sortOrder": 1,"lastModificationDate": 1391629179}]');
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            return res;
        }
    }

    public class MailResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setBody('[{"id": 7905,"toContactId": 15469,"toAddress": "theowolfshaar@hetnet.nl","ccAddresses": null,"subject": "Uw Moving Intelligence diensten verlopen bijna","body": "testtest","sentDate": 1413876152}, {"id": 7905,"toContactId": 15469,"toAddress": "theowolfshaar@hetnet.nl","ccAddresses": null,"subject": "Uw Moving Intelligence diensten verlopen bijna","body": "testtest","sentDate": 1413876152}]');
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            return res;
        }
    }

    public class VoucherResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setBody('[{"id": 1615,"voucherCode": "T21C67A","createDate": 1357081200,"endDate": 1372802400,"createdByContactId": 17492,"requestedByContactId": 15498,"value": 7.89,"spent": null,"accountId": 1,"installationId": 33,"hardwareId": 449,"dealerTaskType": "Uitbouw","reason": null,"status": "Verlopen"}]');
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            return res;
        }
    }

    public class LocationResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setBody('{"installationId": 1234,"gpsDate": 1465205084,"latitude": "51641770","longitude": "4594324","speed": 0,"direction": 128,"altitude": 6,"road": "Lindonk","houseNumber":"2","postalCode": "4761CT","city": "Zevenbergen|m:Moerdijk","country": "Nederland"}');
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);

            return res;
        }
    }

    public class IncidentResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('[{"id":40130,"installationId":1234,"hardwareId":1234,"startDate":1390982112,"endDate":1391629179,"test":"Motorcontact","descriptionDetected":"Geen motorcontact in testperiode, maar wel 64 verschillende GSM-cellen. Vermoeden op beweging zonder motorcontact bestaat.","descriptionSolved":"-"}]');
            res.setStatusCode(200);

            return res;
        }
    }

    //simple mock used to return a 200 statuscode
    public class HandleSendResponseMock implements HttpCalloutMock{
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);

            return res;
        }
    }

    public class ExactMock implements HttpCalloutMock {
        public Boolean invoicePrinted = true;
        public HttpResponse respond(HttpRequest req){
            String body = '';

            //system.debug(req);
            if (req.getMethod() == 'GET' && req.getEndpoint().contains('BankAccounts')) {
                body = '{"d":{"results":[{"ID": "bankaccount_sync","Main":false}]}}';
            } else if(req.getMethod() == 'GET' && req.getEndpoint().contains('SalesInvoices') && this.invoicePrinted){
                body = '{"d":{"results":[{"InvoiceID": "invoice_sync", "InvoiceNumber": "123", "Status": "50"}]}}';
            } else if (req.getMethod() == 'GET' && req.getEndpoint().contains('SalesOrderLines')) {
                body = '{"d":{"results":[{"Code": "code","ID": "70c625f4-b8c9-4aa8-9272-06ac96d6a901", "Item": "70c625f4-b8c9-4aa8-9272-06ac96d6a902"}]}}';
            } else if (req.getMethod() == 'GET'){
                body = '{"d":{"results":[{"Code": "code","ID": "70c625f4-b8c9-4aa8-9272-06ac96d6a901"}]}}';
            } else if(req.getEndpoint().contains('Addresses')){
                body = '{"d":{"ID": "address_sync"}}';
            } else if(req.getEndpoint().contains('BankAccounts')){
                body = '{"d":{"ID": "bankaccount_sync"}}';
            } else if(req.getEndpoint().contains('Accounts')){
                body = '{"d":{"ID": "account_sync","code": "87654321"}}';
            } else if(req.getEndpoint().contains('Contacts')){
                body = '{"d":{"ID": "contact_sync"}}';
            } else if(req.getEndpoint().contains('DirectDebitMandates')){
                body = '{"d":{"ID": "mandate_sync"}}';
            } else if(req.getEndpoint().contains('SalesOrders')){
                body = '{"d":{"OrderID": "order_sync", "OrderNumber": 12345}}';
            } else if(req.getEndpoint().contains('Items')){
                body = '{"d":{"results":[{"Code": "code","ID": "70c625f4-b8c9-4aa8-9272-06ac96d6a901"}]}}';
            } else if(req.getEndpoint().contains('SalesInvoices')){
                body = '{"d":{"ID": "invoice_sync"}}';
            } else if(req.getEndpoint().contains('PrintedSalesInvoices')){
                body = '{"d":{"ID": "??_sync"}}';
            }
            //system.debug(body);

            HttpResponse res = new HttpResponse();
            res.setBody(body);
            res.setStatusCode(200);
            return res;
        }
    }

    public class OAuthMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setBody('{"access_token": "new_access", "refresh_token": "new_refresh", "expires_in": 600, "token_type": "refresh"}');
            res.setStatusCode(200);
            return res;
        }
    }

    public class PlatformMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req){
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setBody('{"success":true,"messages":["Successfully upserted contractor with id 78729, salesforceId 0011q00001DTDGmAAP"],"addedRecords":[{"type":"Account","id":78729,"sfId":"0011q00001DTDGmAAP"}]}');
            res.setStatusCode(200);
            return res;
        }
    }
}