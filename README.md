# Webasyst

[![CI Status](https://img.shields.io/travis/viktkobst/Webasyst.svg?style=flat)](https://travis-ci.org/viktkobst/Webasyst)
[![Version](https://img.shields.io/cocoapods/v/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![License](https://img.shields.io/cocoapods/l/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)
[![Platform](https://img.shields.io/cocoapods/p/Webasyst.svg?style=flat)](https://cocoapods.org/pods/Webasyst)

## Requirements

iOS version 13.0 or higher

## Installation

Webasyst is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'Webasyst'
```
And execute in the terminal while in the project folder
```ruby
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

* **configure** Webasyst library configuration method
    *Parameters:*
        ***bundleId**: Bundle Id of your application, required for authorization on the server*
        ***clientId**: Client Id of your application*
        ***host**: application server host*

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

**Company:** 1312 Inc. *hello@1312.io*. 
**Developer:** Viktor Kobykhno, *ViktkobST@gmail.com*

## License

Webasyst is available under the LGPL license. See the LICENSE file for more info.
