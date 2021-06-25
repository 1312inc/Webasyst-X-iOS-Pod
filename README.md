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
it, simply add the following line into your Podfile:

```
pod 'Webasyst'
```
And execute it in the terminal while in the project folder
```
pod install
```

## Library configuration

The library requires an initial setup. The following steps are needed:
1) Import the library into your project's AppDelegate file
```
import Webasyst
```
2) In the root of your project, create a configuration file Webasyst.plist, which has the following fields

```
"clientId": String //  *host of your server, or the host of the Webasyst central server**clientId of your application*
"host": String //  *host of your server, or the host of the Webasyst central server*
"scope": String // *the scope required by your application (separated by commas)*
```

***You can see an example file in the project repository, the file Webasyst.sample.plist***

After creating this file, in the didFinishLaunchingWithOptions method of the AppDelegate file, call the WebasystApp configuration method 
```
let webasyst = WebasystApp()
webasyst.configure()
```
3) After configuration of the bibiloteca, you can easily use the Webasyst bibiloteca anywhere in your application

**Warning!** 
After retrieving the list of user settings at login, the library will set the active setting from the list to UserDefaults, by the selectDomainUser key

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
    
* **getAuthCode** Method for requesting a confirmation code for authorization via WAID without a browser.
***Parameters:***
        ***value:** Email or phone number to which a confirmation code should be sent;*
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

        `invalid_phone`: An invalid string is passed as a phone number.

        `request_timeout_limit`: Repeat request was sent before timeout was expired.

        `sent_notification_fail`: The server was unable to send the code.

        `server_error`: Server error.

        `undefined`: Unknown error, in the value error, transmits the text of the error.
        ```
    
* **sendConfirmCode** Sending a confirmation code after calling the getAuthCode method.
    ***Parameters:***
        ***code:** Code received by the user via e-mail or text message;*
        ***success:** Closure performed after the method has been executed;*
    ***Returns:** Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain;*
    
* **checkUserAuth** User authentication check on Webasyst server.
    ***Parameters:***
        ***completion:** The closure performed after the check returns a Bool value of whether the user is authorized or not;*
    ***Returns:** Returns user's status in the application (.authorized/.nonAuthorized/.error(message: String));*
    
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
    
* **logOutUser** Logs out a user from the account and deletes all records in the database
    ***Returns:*** Boolean value of deauthorization success;
        
## Errors
*In case of an error, it will be displayed in the XCode console with the label Webasyst error. You need to specify the error code and the text of the message while contacting technical support.*

Example of an error
```ruby
Error Domain=Webasyst warning: https://1312.io The data couldn’t be read because it was missing. Code=205 "(null)"
```

* **200:** Successful implementation of the method
* **205:** Non-critical error, method ran, but with an alert
* **400:** Network layer error while working with the central WAID server
* **401:** Network layer error while working with the user installation server
* **500:** General library database error
* **501:** Database error while working with the list of user settings
* **502:** Database error while working with a user profile

## Author

**Company:** 1312 Inc. *hello@1312.io*
**Developer:** Viktor Kobykhno *ViktkobST@gmail.com*

## License

Webasyst is available under the LGPL license. See the LICENSE file for more info.
