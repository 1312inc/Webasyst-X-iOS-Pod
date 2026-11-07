# Webasyst

[![CI Status](https://img.shields.io/travis/viktkobst/Webasyst.svg?style=flat)](https://travis-ci.org/viktkobst/Webasyst)
[![Version](https://img.shields.io/cocoapods/v/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![License](https://img.shields.io/cocoapods/l/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![Platform](https://img.shields.io/cocoapods/p/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)

## Requirements

- iOS 13.0+ 
- Xcode 11+
- Swift 5.1+

## Demo app

TLDR: Boilerplate app using the Webasyst library is available here: **https://github.com/1312inc/Webasyst-X-iOS**

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

## Local profile and installation storage

The local Core Data storage keeps its existing main-queue context. Reads, writes,
conversion to `UserInstall` / `ProfileData`, and context reset execute on its queue. The
existing storage methods remain synchronous and may be called from either the
main queue or a background queue. Background callers wait for the context queue;
they must not be synchronously awaited by the main thread. No managed objects
leave the context queue.
The SQLite location and model are unchanged; no data migration is required.

This applies to local storage, and does not change the callback queues of network
or authentication methods. Native queue and existing-database regression checks
are in [Tests/CoreDataQueue](Tests/CoreDataQueue).

## Library configuration

The library requires an initial setup. The following steps are needed:
1) Import the library into your project's AppDelegate file
```
import Webasyst
```
2) In the root of your project, create a configuration file ``Webasyst.plist``, which has the following fields (use the demo  app's [Webasyst.plist.example.plist](https://github.com/1312inc/Webasyst-X-iOS/blob/master/Webasyst%20X/Webasyst.plist.example.plist) file as a reference):

```
"clientId": String //  clientId of your application. Example: "72at75391ea785412a24f4568528ed49"
"host": String //  Webasyst ID auth domain: "www.webasyst.com"
"scope": String // the scope required by your application (separated by dot). Example: "site.blog.shop"
```

Get your Webasyst ID auth client id here: https://www.webasyst.com/my/waid/apps/

Webasyst ID API documentation: https://developers.webasyst.com/docs/features/webasyst-id-auth/resources-server-api/

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

* **url** Return url for local storage.

* **getDefaultLocalizedString** Returns the NSLocalizedString contained in the Webasyst localisation files.
    * ***Parameters:***
        * ***key:** Parameter for NSLocalizedString method;*
        * ***comment:** Parameter for NSLocalizedString method;*
    * ***Returns:*** String returned by NSLocalizedString;

* **requestFullScreenConfetti** Start a confetti animation for selected viewController.
    * ***Parameters:***
        * ***viewController:** UIViewController for which the confetti animation will be called;*

* **getToken** A method for getting Webasyst tokens.
    * ***Parameters:***
        * ***tokenType:** Type of token (Access Token or Refresh Token);*
    * ***Returns:*** Requested token in string format;
    
* **authWebasyst (DEPRECATED!!!)** Webasyst server authorization method. ![#f03c15]  `#f03c15`
	* ***Parameters:***
        * ***navigationController:** UINavigationController to display the OAuth webasyst modal window;*
    	* ***action:** Closure to perform an action after authorization;*
    	
* **oAuthLogin** The method presents a webView with a Webasyst authorisation form. After successful completion of the form, the user is authenticated and the user status is returned.
	* ***Parameters:***
    	* ***merge:** Parameter that is responsible for merging accounts;*
        * ***code:** Parameter responsible for merging accounts, which is obtained from the 'mergeTwoAccs' method;*
        * ***navigationController:** UINavigationController to display the OAuth webasyst modal window;*
        * ***action:** Closure to perform an action after authorization with status of user;*

        ```
        UserStatus

        Values:
        
           `authorizedButProfileIsEmpty`: Status when a user is authorised but their profile is empty.
        
           `authorizedButNoneInstalls`: Status when a user is authorised but has not installs.
        
           `authorizedButNoneInstallsAndProfileIsEmpty`: Status when a user is authorised but has not installs and their profile is empty.
        
           `authorized`: Status when user is authorized.
        
           `networkError(String)`: State when the network is unavailable.
        
           `nonAuthorized`: Status when user is not authorized.
        
           `error(message: String)`: Status when the server returned an error.
        ```
        
* **oAuthAppleID** Authorization in Webasyst with an Apple ID.
	* ***Parameters:***
    	* ***authData:** Authorization data sent by the Apple ID authorization controller;*
        * ***result:** Closure with result of authorization;*
        
* **mergeResultCheck** Merge result check.
	* ***Parameters:***
    	* ***completion:** The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one;*
    
* **getAuthCode** Method for requesting a confirmation code for authorization via WAID without a browser.
	* ***Parameters:***
    	* ***value:** Email or phone number to which a confirmation code should be sent;*
        * ***type:** Value type(.email/.phone);*
        * ***success:** Closure performed after the method has been executed. Contains the status of code sent to the user by email or text message, see the AuthResult documentation for a detailed description of the statuses;*

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
    
* **sendConfirmCode** Sending a confirmation code after calling the getAuthCode method or after reading qr-code.
    * ***Parameters:***
   		* ***type:** Type of confirmation code;*
        * ***code:** Code received by user by e-mail or text message or qr content;*
        * ***success:** Closure performed after the method has been executed. Bool value whether the server has accepted the code, if true then the tokens are saved in the Keychain;*

* **checkInstallApp** App installation.
    * ***Parameters:***
   		* ***app:** Application name;*
        * ***completion:** The closure performed after the check returns a Bool value about whether the result was successful or not and a description of the error, if there was one;*
        
* **checkLicense** Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    * ***Parameters:***
   		* ***app:** Application name;*
        * ***completion:** The closure performed after the check returns a Bool value of whether the user is authorized or not;*

* **extendLicense** Tries to find a free (not tied to the installation) license from the user whose token is accessed by the mobile application. If there is one, then binds it to the installation. Otherwise, it creates a trial product license tied to the installation.
    * ***Parameters:***
    	* ***type:** Type of subscription plan;*
   		* ***date:** Subscription cut-off date;*
        * ***completion:** The closure performed after the check returns a Bool value of whether the user is authorized or not;*   
        
* **defaultChecking** User authentication check on Webasyst server.
    * ***Parameters:***
        * ***completion:** The closure returns the existing `CheckingType` startup state;*
        
* **checkUserAuth** User authentication check on Webasyst server.
    * ***Parameters:***
        * ***completion:** Updating the user token, and checking authorization. Returns user status in the application;*
 
 * **mergeTwoAccs** A new free WAID contact connected to the opposite application can oppose another existing WAID contact.
    * ***Parameters:***
        * ***completion:** Returns result with code to merge or error;*
        
* **deleteAccount** The method sends a request to delete the current account and returns the result.
    * ***Parameters:***
        * ***completion:** Account deletion result or error;*

* **getAllUserInstall** Getting user install list.
    * ***Parameters:***
        * ***completion:** List of all user installations in UserInstall format (name, clientId, domain, accessToken, url);*
        
* **updateUserInstalls** Updating and Getting user install list from server
    * ***Parameters:***
        * ***completion:** List of all user installations in UserInstallCodable format (name, clientId, domain, accessToken, url);*
    
* **getUserInstall**  Obtaining user installation.
    * ***Parameters:***
        * ***clientId:** clientId setting;*
    * ***Returns:*** Installation in User Install format;
    
* **deleteInstall** Deletes the installation from the database.
    * ***Parameters:***
        * ***clientId:** clientId install;*
        
* **getProfileData** Returns user profile data
    * ***Returns:*** User profile data in ProfileData format;

* **updateUserImage**  Update current user image.
    * ***Parameters:***
        * ***image:** Image to update;*
        * ***success:** Closure performed after executing the method. Result value which can be successfully or errorable;*
        
* **deleteUserImage**  Delete current user image.
    * ***Parameters:***
        * ***image:** Closure performed after executing the method. Result value which can be successfully or errorable;*
              
* **changeCurrentUserData**  Change the data of the current user.
    * ***Parameters:***
        * ***profile:** Pass the current data model with user information;*
        * ***success:** Closure performed after executing the method. Result value which can be successfully or errorable;*
    
* **createWebasystAccount**  Creating a new Webasyst account.
    * ***Parameters:***
        * ***bundle:** Bundle of the account being created;*
        * ***plainId:** Plain id of the account being created;*
        * ***accountDomain:** Domain of the account being created;*
        * ***accountName:** Name of the account being created;*
        * ***completion:** Contains a result of creating and renaming of new account. Reutrns client id and url of new account if successed;*
    
* **logOutUser** Logs out a user from the account and deletes all records in the database.
    * ***Parameters:*** 
   		* ***completion:** Boolean value of deauthorization success;*
        
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

## License

Webasyst is available under the LGPL license. See the LICENSE file for more info.

## Authentication failure handling

`refreshAccessToken(_:)` keeps its existing `(Bool) -> Void` callback. `false` means that the operation did not finish successfully; transport errors, HTTP 429/5xx, invalid responses and temporary Keychain failures retain the current session. Stale Apple ID email-confirmation handlers cannot replace or sign out a later session. Only an OAuth `invalid_grant` response (HTTP 400/401) for the current refresh operation triggers automatic local logout. An access-token 401 from a protected API does not by itself revoke the refresh credential. Explicit `logOutUser()` retains its existing logout behavior.

Concurrent refresh calls in the same application process share one request. Login, logout and token commits are serialized; obsolete responses cannot replace a newer login. Callbacks for cached startup and preflight failures may be synchronous. Network authentication completions are delivered on the main queue. Applications must not block the main queue while waiting for SDK callbacks.

The existing local, shared and legacy Keychain identities and accessibility are retained. Shared Keychain remains optional. Cross-app restoration exchanges the shared access token before storing local credentials; a transient restoration failure does not erase another application's shared credential. A legacy refresh token can migrate without an access token. A persisted local logout marker prevents undeleted Keychain items from reappearing after unlock or restart; successful separate watchOS setters unblock only the credential they replace. Updates use `SecItemUpdate` and publish the existing `accessTokenUpdated`/`refreshTokenUpdated` notifications after a complete pair is saved.

If persistence fails after receiving rotated tokens, the SDK keeps the received pair in memory and retries persistence on the next refresh call before making another network request. A process termination before any successful durable write, or a lost server response after rotation, requires server-side recovery policy; the client does not blindly replay refresh requests or switch OAuth hosts. Domain selection still follows the configured host and device region.

Applications can observe `Notification.Name.webasystAuthDiagnostic` and forward its `userInfo` to their logging service. Fields are limited to operation, outcome, configured authentication host, duration, failure category, HTTP status and underlying error domain/code. Tokens, request/response bodies, user information and installation URLs are excluded. This notification does not add a Firebase dependency. `WebasystError` additionally exposes optional `underlyingErrorDomain` and `underlyingErrorCode`; the previous initializer is preserved.

The built-in OAuth screen preserves the actual network, server, decoding or Keychain error instead of replacing every failed exchange with a generic access-token message. Existing OAuth `errorValue` metadata remains available to consumers.

## Authentication regression tests

Run from the repository root:

```sh
python3 scripts/test-auth.py
python3 scripts/check-sdk.py --platform all
```

The first command creates an isolated simulator, builds the actual Webasyst framework and XCTest host, runs controlled HTTP-response and native-Keychain tests, and removes only its own simulator. It does not use a real account or make live API requests. Each command prints its verdict to stdout and preserves a failure exit code. `--udid` uses an already reserved simulator without deleting it; `--derived-data` reuses an incremental build directory.

The distributed minimum versions remain iOS 13/watchOS 7. By default, verification builds use iOS 15/watchOS 9 because Xcode 27 SDKs reject older deployment targets. To compile the unchanged minimum versions, select a compatible toolchain with `DEVELOPER_DIR` and run `python3 scripts/check-sdk.py --platform all --minimum-os`. A compilation check does not replace runtime testing on the minimum supported OS. Cross-process shared-Keychain access, server token rotation policy and real-account acceptance must also be verified in the consuming applications before release.
