# Webasyst

[![CI Status](https://img.shields.io/travis/viktkobst/Webasyst.svg?style=flat)](https://travis-ci.org/viktkobst/Webasyst)
[![Version](https://img.shields.io/cocoapods/v/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![License](https://img.shields.io/cocoapods/l/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![Platform](https://img.shields.io/cocoapods/p/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)

## Requirements

- iOS 13.0+ 
- Xcode 11+
- Swift 5.1+

## Installation

Webasyst is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```
pod 'Webasyst'
```
And execute in the terminal while in the project folder
```
pod install
```

## Library configuration

The library requires initial setup. The following steps are required:
1) Import the library into your project's AppDelegate file
```
import Webasyst
```
2) In the didFinishLaunchingWithOptions method, call the WebasystApp configuration method
```
let webasyst = WebasystApp()
webasyst.configure(
    clientId: *clientId of your application*, 
    host: *host of your server, or the host of the Webasyst central server*, 
    scope: *the scope required by your application (separated by commas)*
)
```
3) After configuring the bibiloteca, you can use the Webasyst bibiloteca anywhere in your application

## Description of methods

*A description of all methods, including all parameters, can be obtained from the XCode autocomplete or via QuickHelp*

* **configure** Webasyst library configuration method.
    ***Parameters:***
        ***bundleId**: Bundle Id of your application, required for authorization on the server;*
        ***clientId**: Client Id of your application;*
        ***host**: application server host;*

* **getToken** A method for getting Webasyst tokens.
    ***Parameters:***
        ***tokenType:** Type of token (Access Token or Refresh Token);*
        ***Returns:*** Requested token in string format;
    
* **authWebasyst (DEPRECATED!!!)** Webasyst server authorization method. ![#f03c15]  `#f03c15`
***Parameters:***
        ***navigationController:** UINavigationController to display the OAuth webasyst modal window;*
    ***action:** Closure to perform an action after authorization;*
    
* **getAuthCode** Method for requesting a confirmation code for authorisation via WAID without a browser.
***Parameters:***
        ***value:** Email or telephone number to which a confirmation code should be sent;*
        ***type:** Value type(.email/.phone);*
        ***success:** Closure performed after the method has been executed;*
        ***Returns:** Status of code sent to the user by email or text message, see AuthResult documentation for a detailed description of statuses;*

        ```
        AuthResult

        Server response when authentication is requested

        Values:

        `success`: Successful request Tokens saved in Keychain.

        `no_channels`: Incorrect clientId.

        `invalid_client`: Not transmitted code_challenge.

        `require_code_challenge`: Not transmitted code_challenge.

        `invalid_email`: An invalid string is passed as an email.

        `invalid_phone`: An invalid string is passed as the phone.

        `request_timeout_limit`: Repeat request sent before timeout expires for repeat request.

        `sent_notification_fail`: The server was unable to send the code.

        `server_error`: Server error.

        `undefined`: Unknown error, in the value error transmits the text of the error.
        ```
    
* **checkUserAuth** User authentication check on Webasyst server.
    ***Parameters:***
        ***completion:** The closure performed after the check returns a Bool value of whether the user is authorized or not;*
    ***Returns:** Returns user status in the application (.authorized/.nonAuthorized/.error(message: String));*
    
* **getAllUserInstall** Getting user install list.
    ***Returns:** List of all user installations in UserInstall format (name, clientId, domain, accessToken, url);*
    
* **getUserInstall**  Obtaining user installation.
    ***Parameters:***
        ***clientId:** clientId setting;*
    ***Returns:*** Installation in User Install format;
    
* **deleteInstall** Deletes the installation from the database.
    ***Parameters:***
        ***clientId:** clientId install;*
        
* **getProfileData** Returns user profile data
    ***Returns:*** User profile data in ProfileData format;
    
* **logOutUser** Exit a user from the account and delete all records in the database.
    ***Returns:*** Boolean value of deauthorization success;
        
## Errors
*In the event of a fault, all errors are displayed in the XCode console with the label Webasyst error. When contacting technical support you need to specify the error code and the message text.*

Example of an error
```ruby
Error Domain=Webasyst warning: https://1312.io The data couldn’t be read because it is missing. Code=205 "(null)"
```

* **200:** Successful implementation of the method
* **205:** Non-critical error, method ran, but with a warning
* **400:** Network layer error when working with the central WAID server
* **401:** Network layer error when working with the user installation server
* **500:** General library database error
* **501:** Database error when working with the list of user settings
* **502:** Database error when working with a user profile

## Author

**Company:** 1312 Inc. *hello@1312.io*
**Developer:** Viktor Kobykhno *ViktkobST@gmail.com*

## License

Webasyst is available under the LGPL license. See the LICENSE file for more info.
