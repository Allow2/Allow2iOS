# Allow2iOS

[![Travis CI](https://travis-ci.org/Allow2/allow2iOS.svg?branch=master)](https://travis-ci.org/Allow2/allow2iOS) [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) ![CocoaPods](https://img.shields.io/cocoapods/v/Allow2iOS.svg) ![Platform](https://img.shields.io/badge/platforms-iOS%209.0+-333333.svg)

Allow2 makes it easy to add parental controls to your apps.

1. [Why should you use Allow2?](#why-should-you-use-Allow2)
2. [Requirements](#requirements)
3. [Integration](#integration)

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

## Requirements

- iOS 8.0+ | macOS 10.10+ | tvOS 9.0+ | watchOS 2.0+
- Xcode 8

## Integration

#### CocoaPods (iOS 9+)

You can use [CocoaPods](http://cocoapods.org/) to install `Allow2iOS` by adding it to your `Podfile`:

```ruby
platform :ios, '9.0'
use_frameworks!

target 'MyApp' do
pod 'Allow2iOS'
end
```

Note that this requires CocoaPods version 36, and your iOS deployment target to be at least 9.0:


#### Carthage (iOS 9+)

You can use [Carthage](https://github.com/Carthage/Carthage) to install `Allow2iOS` by adding it to your `Cartfile`:

```
github "Allow2iOS/Allow2Framework"
```

#### Swift Package Manager

You can use [The Swift Package Manager](https://swift.org/package-manager) to install `Allow2iOS` by adding the proper description to your `Package.swift` file:

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

