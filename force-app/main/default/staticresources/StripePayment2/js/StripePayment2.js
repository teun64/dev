var stripe;
var elements;
var card;
var paymentElement;
const queryString = window.location.search;
var clientSecret;
var publicKey;
var paymentResult;
console.log("In the javascript");
var isInitialized = false;  // Global variable to track initialization

window.addEventListener('message', function(event) {
    if (event.data.clientSecret) {
        clientSecret = event.data.clientSecret;
    }
    if (event.data.publicKey) {
        publicKey = event.data.publicKey;
    }
    if (event.data.theme) {
        themeSetting = event.data.theme;
    }
    if (event.data.paymentResult) {
        paymentResult = event.data.paymentResult;
    }
    if (clientSecret && publicKey && !isInitialized) {
        console.log("clientSecret : " + clientSecret);
        console.log("publicKey : " + publicKey);
        initializeStripe(themeSetting);
        isInitialized = true;
    }  
}, false);



function initializeStripe(theme) {
	// Set Publishable key of your Stripe Account.
    
stripe = Stripe(publicKey);


const appearance = {
    theme: theme || 'stripe',
    labels: 'floating'
  };
  const options = {
    layout: {
      type: 'tabs',
      defaultCollapsed: false,
    }
  };
  const elementsOptions = {
    appearance: appearance,
    clientSecret: clientSecret
};
elements = stripe.elements(elementsOptions);

const paymentElement = elements.create('payment', options);
paymentElement.mount('#payment-element');
    // Handle validation errors from the card Element. 
    paymentElement.addEventListener('change', function(event) { 
        var displayCardError = document.getElementById('payment-element-Errors'); 
        // get cardErrors Div 
        if (event.error) { 
            // Show Validation errors 
            displayCardError.textContent = event.error.message; 
        } 
        else { 
            displayCardError.textContent = ""; 
        } 
    }); 
}; 
async function validateCard(){ 
    const result = await stripe.confirmPayment({
        elements,
        confirmParams: {
          // Make sure to change this to your payment completion page
          return_url: "http://www.google.com"
        },
        redirect: 'if_required',
      });

    if (result.error) {
        if (result.error.type === "card_error" || result.error.type === "validation_error") {
            showMessage(result.error.message);
        } else {
            showMessage("An unexpected error occurred.");
        }
    } else {
        // If there's no error, you might want to check the payment status right away.
        checkStatus();
    }

    setLoading(false);
}


// Fetches the payment intent status after payment submission
async function checkStatus() {

  const { paymentIntent } = await stripe.retrievePaymentIntent(clientSecret);

  paymentResult = paymentIntent.status;

  switch (paymentResult) {
    case "succeeded":
      showMessage("Payment succeeded!");
      hidePaymentElement();
      break;
    case "processing":
      showMessage("Your payment is processing.");
      hidePaymentElement();
      break;
    case "requires_payment_method":
      showMessage("Your payment was not successful, please try again.");
      break;
    default:
      showMessage("Something went wrong.");
      break;
  }
}

function hidePaymentElement() {
    const paymentEl = document.getElementById('payment-element');
    if (paymentEl) {
        paymentEl.style.display = 'none';
    }
}

function generateToken(intent){ 
    var tokenId = JSON.stringify(intent.id); 
}

function showMessage(messageText) {
    const messageContainer = document.querySelector("#payment-message");
  
    messageContainer.classList.remove("hidden");
    messageContainer.textContent = messageText;
  
    setTimeout(function () {
      messageContainer.classList.add("hidden");
      messageContainer.textContent = "";
    }, 20000);
  }
  
  // Show a spinner on payment submission
  function setLoading(isLoading) {
    let submitButton = document.getElementById("submitButton");
    let spinner = document.querySelector("#spinner");
    let buttonText = document.querySelector("#button-text");
    
    if (isLoading) {
        // Show spinner and hide button text
        if(spinner) spinner.classList.remove("hidden");
        if(buttonText) buttonText.classList.add("hidden");
        
        // Visually "disable" the button
        if(submitButton) submitButton.classList.add('disabled');
    } else {
        // Hide spinner and show button text
        if(spinner) spinner.classList.add("hidden");
        if(buttonText) buttonText.classList.remove("hidden");
        
        // Visually "enable" the button
        if(submitButton) submitButton.classList.remove('disabled');
    }
}
