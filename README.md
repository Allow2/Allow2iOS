# Allow2iOS

[![Travis CI](https://travis-ci.org/Allow2/allow2iOS.svg?branch=master)](https://travis-ci.org/Allow2/allow2iOS) [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) ![CocoaPods](https://img.shields.io/cocoapods/v/Allow2.svg) ![Platform](https://img.shields.io/badge/platforms-iOS10.0+-333333.svg)

Allow2 makes it easy to add parental controls to your apps.

1. [Why should you use Allow2?](#why-should-you-use-allow2)
2. [What's it look like?](#whats-it-look-like)
3. [Requirements](#requirements)
4. [Integration](#integration)

refer to https://github.com/Allow2/Allow2.github.io/wiki for more details.

## Why should you use Allow2?

Parental controls are incredibly complex and difficult to get correct and for a parent, there is nothing worse than having to log in or open up yet another parental control interface on another app and reconfigure it every other day.

Allow2 solves the problem once and for all:

1. Leverage the powerful Allow2 platform completely for free (no developer licensing fees)
2. Add parental controls in a matter of hours and don't worry about implementing heaps of interfaces.
3. Show your community responsibility and support parents, this helps to bring more users to your apps.

Really, you should be able to add extensive and powerful parental controls to your apps in a matter of hours or (at most) a couple of days.

With Allow2 all you have to do to check if something can be used and record it's usage is:

```swift
let allow2Activities = [
    Allow2.Allow2Activity(activity: Allow2.Activity.Internet, log: true), // this is an internet based app
    Allow2.Allow2Activity(activity: Allow2.Activity.Gaming, log: true),   // and it's gaming related, can also use "Messaging", "Social", "Electricity" and more...
]
Allow2.shared.check(allow2Activities)
```

And don't worry about having to tell other parts of your app. It's done for you automatically (just listen for the Allow2CheckResultNotification)!

```swift
func Allow2CheckResultNotification(notification:NSNotification) {
    guard let userInfo = notification.userInfo,
    let result  = userInfo["result"] as? Allow2CheckResult else {
        print("No Allow2CheckResult found in notification")
        return
    }

    dispatch_async(dispatch_get_main_queue()) {
        self.allow2View.hidden = result.allowed

        if (!result.allowed) {
            // configure the block screen to explain the issue
            self.allow2View.result = result
        }
    }
}

```

## What's it look like?

| Screenshot | Description |
| --- | --- |
| <img src="https://github.com/Allow2/Allow2iOS/blob/master/Screenshots/pairing.jpg" alt="Pairing" width="150"/> | Pairing <br> Initial Setup |
| <img src="https://github.com/Allow2/Allow2iOS/blob/master/Screenshots/select.jpg" alt="Choose Child" width="150"/> | When there is more than one child, and the app can be used by any child |
| <img src="https://github.com/Allow2/Allow2iOS/blob/master/Screenshots/pin.jpg" alt="Enter Pin" width="150"/> | Before a child can use the app, they need to enter their pin <br> (if more than one child) |
| <img src="https://github.com/Allow2/Allow2iOS/blob/master/Screenshots/banned.jpg" alt="Banned" width="150"/> | If usage is not allowed at that time, or they ran out of quota, or have been banned. |
| <img src="https://github.com/Allow2/Allow2iOS/blob/master/Screenshots/request.jpg" alt="Request" width="150"/> | Children can request changes directly from within your game or app |

## Requirements

- iOS 8.0+ | macOS 10.10+ | tvOS 9.0+ | watchOS 2.0+
- Xcode 8

## Integration

#### CocoaPods (iOS 9+)

You can use [CocoaPods](http://cocoapods.org/) to install `Allow2` by adding it to your `Podfile`:

```ruby
platform :ios, '9.0'
use_frameworks!

target 'MyApp' do
    pod 'Allow2'
end
```

Note that this requires CocoaPods version 36, and your iOS deployment target to be at least 9.0:


#### Carthage (iOS 9+)

You can use [Carthage](https://github.com/Carthage/Carthage) to install `Allow2` by adding it to your `Cartfile`:

```
github "Allow2/Allow2Framework"
```

#### Swift Package Manager

You can use [The Swift Package Manager](https://swift.org/package-manager) to install `Allow2` by adding the proper description to your `Package.swift` file:

```swift
import PackageDescription

let package = Package(
name: "YOUR_PROJECT_NAME",
targets: [],
dependencies: [
.Package(url: "https://github.com/Allow2/allow2iOS.git", versions: Version(1,0,0)..<Version(2, .max, .max)),
]
)
```

Note that the [Swift Package Manager](https://swift.org/package-manager) is still in early design and development, for more information checkout its [GitHub Page](https://github.com/apple/swift-package-manager)

#### Manually (iOS 9+)

To use this library in your project manually you may:  

1. drag in the whole Allow2Framework.xcodeproj

## Usage

#### Initialization

```swift
import Allow2
```

There are some basic options required to get started and some optional ones.

#### Create the app or device and get a token - REQUIRED

First of all, you need to set up the device in the developer portal, so head over there, signup (all free), and create your app/device:

[https://developer.allow2.com/](https://developer.allow2.com/)

then you need to set the token in the library before you can use any functions:

```swift
func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    ...
    
    Allow2.shared.deviceToken = "<DEVICE TOKEN GOES HERE>"
    
    ...
}
```

#### Set the environment - OPTIONAL

By default, the system will ALWAYS connect to the production environment. You can safely set up new apps in the developer portal and design and use them in the production system without any issues and this will be the most anyone will want to do.

However, the Allow2 platfom is also updated on a regular basis and as changes are bought to realisation, they flow through a standard release process that we allow developers to paticipate in. At this time, we allow developers to test in the "sandbox" environment (essentially "beta") and in the "staging" environment (essentially "alpha"). So you CAN set the system to use one of these environments, BUT use them at your own peril!

```swift
func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    ...

    Allow2.shared.env = .sandbox

    ...
}
```

#### Convenience setup - OPTIONAL

Allow2 for iOS provides a convenience setup in case you are building into multiple environments yourself, you can pass a plist (directly out of your bundle if you wish!) into the convience property setter to handle one line config and easily manage multiple build targets:

```xml
<key>Allow2</key>
<dict>
    <key>DeviceToken</key>
    <string>DEVICETOKEN</string>
    <key>Environment</key>
    <string>staging</string>
</dict>
```

Then you can pass this straight in from your Bundle:

```swift
func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    ...

    Allow2.shared.setPropsFromBundle(Bundle.main.infoDictionary?["Allow2"])

    ...
}
```

Any parameter that is not recognised will be ignored, so Environment: Invalid will essentially leave it as the default or whatever it was set to earlier.

