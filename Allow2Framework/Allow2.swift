//
//  Allow2.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 6/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

/**
 * Result from a successful check call
 */
public struct Allow2PairResult {
    public var children : [ Allow2Child ]
}

public struct Allow2Child {
    public var id : UInt64
    public var name : String
    public var pin : String
}

/**
 *  Error Types
 */
public enum Allow2Error: Error {
    case NotPaired
    case AlreadyPaired
    case MissingChildId
    case NotAuthorised
    case InvalidResponse
    case Other(message : String)
}


/**
 * Response from the various calls
 */
public enum Allow2Response {
    case Error(Error)
    case PairResult(Allow2PairResult)
    case CheckResult(Allow2CheckResult)
    case Request(Bool)
    
    static func parseFromJSON(response : JSON) -> Allow2Response {
        guard response["error"] != "invalid pairId" else {
            // special case, no longer controlled
            Allow2.shared.userId = nil
            Allow2.shared.pairId = nil
            Allow2.shared.childId = nil
            Allow2.shared._children = []
            Allow2.shared._dayTypes = []
            return .CheckResult(Allow2CheckResult(
                allowed: true,
                activities: [],
                dayTypes: [],
                allDayTypes: [],
                children: []
                ))
        }
        
        if let requestSent = response["requestSent"].bool {
            return .Request(requestSent)
        }
        
        guard let allowed = response["allowed"].bool else {
            return .Error(Allow2Error.InvalidResponse)
        }
        let activities = response["activities"]
        let dayTypes = response["dayTypes"]
        let children = response["children"]
        let allDayTypes = response["allDayTypes"]
        Allow2.shared._children = children.arrayValue.map { (child) -> Allow2Child in
            return Allow2Child(id: child["id"].uInt64Value,
                               name: child["name"].stringValue,
                               pin: child["pin"].stringValue)
        }
        
        return .CheckResult(Allow2CheckResult(
            allowed: allowed,
            activities: activities,
            dayTypes: dayTypes,
            allDayTypes: allDayTypes,
            children: children
            ))
    }
}


extension Notification.Name {
    public static let allow2PairingChangedNotification = Notification.Name("Allow2PairingChangedNotification")
    public static let allow2CheckResultNotification = Notification.Name("Allow2CheckResultNotification")
}

public class Allow2 {

    public var deviceToken : String? = "Not Set"
    public var env : EnvType = .production

    var userId : String? {
        get { return (UserDefaults.standard.object(forKey: "Allow2UserId") as? String) }
        set { UserDefaults.standard.set(newValue, forKey: "Allow2UserId") }
    }
    var pairId : String? {
        get { return (UserDefaults.standard.object(forKey: "Allow2PairId") as? String) }
        set { UserDefaults.standard.set(newValue, forKey: "Allow2PairId") }
    }

    public var isPaired : Bool {
        get {
            return (self.userId != nil) && (self.pairId != nil)
        }
    }

    public enum EnvType : String {
        case production = "production"  // ALWAYS use this one (unless you really want to try new features in Dev mode).
        
        // _DO NOT_ release your products using either of these settings
        case sandbox = "sandbox"        // currently pointing to staging, so use with care.
        case staging = "staging"        // access to bleeding edge functionality - CAUTION!
    
        public init(rawValue: String) {
            switch rawValue {
            case "sandbox": self = .sandbox
            case "staging": self = .staging
            default: self = .production
            }
        }
    }

    var _children : [ Allow2Child ] = []
    var _dayTypes : [ Allow2Day ] = []

    public var children : [ Allow2Child ] {
        get {
            return _children
        }
    }
    
    public var dayTypes : [ Allow2Day ] {
        get {
            return _dayTypes
        }
    }
    
    // used only if the device is locked to a specific user.
    public var childId : String? {
        get { return (UserDefaults.standard.object(forKey: "Allow2ChildId") as? String) }
        set { UserDefaults.standard.set(newValue, forKey: "Allow2ChildId") }
    }
    
    // todo: should do this better
    public static var allow2BlockViewController : Allow2BlockViewController {
        get {
            let allow2FrameworkBundle = Bundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewController(withIdentifier: "Allow2BlockViewController") as! Allow2BlockViewController
        }
    }
    
    // todo: should do this better
    public static var allow2LoginViewController : Allow2LoginViewController {
        get {
            let allow2FrameworkBundle = Bundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewController(withIdentifier: "Allow2LoginViewController") as! Allow2LoginViewController
        }
    }
    
    // todo: should do this better
    public static var allow2PairingViewController : Allow2PairingViewController {
        get {
            let allow2FrameworkBundle = Bundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewController(withIdentifier: "Allow2PairingViewController") as! Allow2PairingViewController
        }
    }

    // todo: should do this better
    public static var allow2RequestViewController : UINavigationController {
        get {
            let allow2FrameworkBundle = Bundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewController(withIdentifier: "Allow2RequestViewController") as! UINavigationController
        }
    }
    

    
    public static var AllowLogo : UIImage {
        get {
            return UIImage(named: "Allow2 Logo", in: Bundle(for: Allow2.self), compatibleWith: nil)!
        }
    }
    
    var apiUrl : String {
        get {
            switch env {
            case .sandbox:
                return "https://sandbox-api.allow2.com"
            case .staging:
                return "https://staging-api.allow2.com"
            default:
                return "https://api.allow2.com"
            }
        }
    }
    
    var serviceUrl : String {
        get {
            switch env {
            case .sandbox:
                return "https://service.allow2.com:9443"
            case .staging:
                return "https://api.allow2.com:9443" //"https://staging-service.allow2.com"
            default:
                return "https://staging-service.allow2.com:9443"
            }
        }
    }
    
    public static let shared = Allow2()
    
    private init (){
        //print("Allow2 has been initialised")
    }
    
    /**
     * cached responses (each expire as required)
     * 
     * Simplistic initial implementation uses the full hashed request as the key, probably should cache more intelligently in future
     */
    var resultCache : [ String : Allow2CheckResult ] = [ : ]
    

    /**
     * Activity descriptor to pass to the check call
     */
    public class Allow2Activity {
        
        var jsonObject : [ String : Any ]
        
        public init(activity: Allow2.Activity, log: Bool = true) {
            jsonObject = [
                "id": activity.rawValue,
                "log": log
            ]
        }
    }
    
    public enum Activity : Int {
        case Internet = 1
    }

    
    /**
     * setPropsFromBundle(Any?)
     *
     * @PARAM possibleBundle    : a dictionary [ String : Any ]
     *
     * Sets parmeters using the supplied dictionary:
     * {
     *    DeviceToken: "YGHGHGHG...",
     *    Environment: "production"         : OPTIONAL, defaults to "production"
     * }
     *
     * Returns Void
     */
    public func setPropsFromBundle(_ possibleBundle: Any?) {
        if let Allow2Props = possibleBundle as? [ String : Any ] {
            if let deviceToken = Allow2Props["DeviceToken"] as? String {
                self.deviceToken = deviceToken
            }
            if let environmentString = Allow2Props["Environment"] as? String {
                self.env = EnvType(rawValue: environmentString)
            }
        }
    }
    
    /**
     * pair(user, password, deviceName)
     *
     * @PARAM user          : login name for Allow2 web portal
     * @PARAM password      : password for Allow2 web portal
     * @PARAM deviceName    : user friendly device name (for identification)
     *
     * Returns error code, or list of child accounts
     */
    public func pair(user : String!, password: String!, deviceName : String!, completion: ((Allow2Response) -> Void)? = nil) {
        
        guard !self.isPaired else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.AlreadyPaired ))
            }
            return
        }
        
        let url = URL(string: "\(apiUrl)/api/pairDevice")
        
        let body : JSON = [
            "user": user,
            "pass": password,
            "deviceToken": self.deviceToken ?? "MISSING",
            "name": deviceName
        ];
        
        var request = URLRequest(url: url!)
        request.httpMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        //json: true,
        
        do {
            request.httpBody = try body.rawData()
            
            let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
                print(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)
                
                // todo: better error handling on data -> JSON
                guard let json = try? JSON(data: data!) else {
                    if (completion != nil) {
                        completion!(Allow2Response.Error(Allow2Error.Other(message: "Invalid Response" )))
                    }
                    return
                }
                
                if let status = json["status"].string {
                    
                    guard status == "success" else {
                        if (completion != nil) {
                            completion!(Allow2Response.Error(Allow2Error.Other(message: json["message"].string ?? "Unknown Error" )))
                        }
                        return
                    }
                    
                    self.pairId = json["pairId"].string
                    self.userId = json["userId"].string
                    let childrenJson = json["children"].array ?? []
                    
                    // todo: maintain the list of children internally
                    
                    if (completion != nil) {
                        var newChildren : [Allow2Child] = []
                        for child in childrenJson {
                            newChildren.append(Allow2Child(id: child["id"].uInt64Value,
                                                           name: child["name"].stringValue,
                                                           pin: child["pin"].stringValue))
                        }
                        self._children = newChildren
                        
                        completion!(Allow2Response.PairResult(Allow2PairResult( children: self.children )))
                    }
                }
            }
            task.resume()
            
        } catch (let err) {
            print(err)
        }
    }
    
    /**
     * check(activities, log, completion)
     *
     * @PARAM activities    : list of Allow2Activity items to check or log
     * @PARAM log           : boolean - should this be logged?  // todo: redundant?
     * @PARAM completion    : callback on completion, returns Allow2Response
     */
    public func check(activities: [Allow2Activity]!, log: Bool = true, completion: ((Allow2Response) -> Void)? = nil) {
        /*guard self.childId != nil else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.MissingChildId ))
            }
            return
        }*/
        check(childId: self.childId, activities: activities, log: log, completion: completion)
    }
    
    /**
     * check(childId, activities, log, completion)
     *
     * @PARAM childId       : ID of child using the device right now
     * @PARAM activities    : list of Allow2Activity items to check or log
     * @PARAM log           : boolean - should this be logged?  // todo: redundant?
     * @PARAM completion    : callback on completion, returns Allow2Response
     */
    public func check(childId: String!, activities: [Allow2Activity]!, log: Bool = true, completion: ((Allow2Response) -> Void)? = nil) {
        
        guard self.isPaired else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.NotPaired ))
            }
            return
        }
        
        var body : JSON = [
            "userId": self.userId!,
            "pairId": self.pairId!,
            "deviceToken": self.deviceToken ?? "MISSING",
            "tz": NSTimeZone.local.identifier,
            "activities": activities.jsonArray,
            "log": log
        ];
        if (childId != nil) {
            body["childId"] = JSON(childId!)
        }
        let key = body.rawString()!
        
        // check the cache first
        if let checkResult = self.resultCache[key] {
            
            if checkResult.expires.timeIntervalSinceNow.sign != .minus {
                // not expired yet, use cached value
                if completion != nil {
                    completion!( Allow2Response.CheckResult(checkResult) )
                }
                return
            }
            
            // clear cached value and ask the server again
            self.resultCache.removeValue(forKey: key)
        }
        
        let url = URL(string: "\(serviceUrl)/serviceapi/check")
        var request = URLRequest(url: url!)
        request.httpMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        //json: true,
        
        do {
            request.httpBody = try body.rawData()
        
            let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
                guard error == nil else {
                    completion?(Allow2Response.Error( error! ))
                    return;
                }
                
                guard data != nil else {
                    completion?(Allow2Response.Error( Allow2Error.InvalidResponse ))
                    return;
                }
                
                print(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)
                
                // interpret the result
                // todo: 403 is disconnected, clear everything out
                
                // handle other errors
                
                // attempt to handle valid response
                // todo: better error handling on data -> JSON
                guard let json = try? JSON(data: data!) else {
                    completion?(Allow2Response.Error( Allow2Error.InvalidResponse ))
                    return;
                }
                
                let result = Allow2Response.parseFromJSON(response: json)
            
                switch result {
                case let .CheckResult(checkResult):
                    
                    // good response, cache the result first
                    self.resultCache[key] = checkResult

                    // notify everyone
                    NotificationCenter.default.post(
                        name: .allow2CheckResultNotification,
                        object: nil,
                        userInfo: [ "result" : checkResult ]
                    )

                    break
                default:
                    completion?(result)
                    return
                }

                // now return the result
                completion?(result)
            }
            task.resume()
            
        } catch (let err) {
            print(err)
            completion?(Allow2Response.Error( err ))
        }
    }
    
    public class Allow2Day {
        public var id : Int {
            get {
                return self.id
            }
        }
        public var name : String {
            get {
                return self.name
            }
        }
        
        init (json: JSON) {
            
        }
    }
}

extension Array where Element:Allow2.Allow2Activity {
    var jsonArray : [[String : Any]] {
        get {
            return self.map() {
                return $0.jsonObject
            }
        }
    }
}

extension Allow2 {
    public func request(dayTypeId: UInt64?, lift: [UInt64]?, message: String?, completion: ((Allow2Response) -> Void)? = nil) {
        
        guard self.isPaired else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.NotPaired ))
            }
            return
        }
        
        var body : JSON = [
            "userId": self.userId!,
            "pairId": self.pairId!,
            "deviceToken": self.deviceToken ?? "MISSING",
            "childId" : JSON(Allow2.shared.childId!),
            "lift": JSON( lift ?? [])
        ];
        if (dayTypeId != nil) {
            body["dayType"] = JSON(dayTypeId!)
            body["changeDayType"] = true
        }
        
        let key = body.rawString()!
        
        let url = URL(string: "\(apiUrl)/request/createRequest")
        var request = URLRequest(url: url!)
        request.httpMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        //json: true,
        
        do {
            request.httpBody = try body.rawData()
            
            let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
                guard error == nil else {
                    completion?(Allow2Response.Error( error! ))
                    return;
                }
                
                guard data != nil else {
                    completion?(Allow2Response.Error( Allow2Error.InvalidResponse ))
                    return;
                }
                
                print(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)
                
                // interpret the result
                // todo: 403 is disconnected, clear everything out
                
                // handle other errors
                
                // attempt to handle valid response
                // todo: better error handling on data -> JSON
                guard let json = try? JSON(data: data!) else {
                    completion?(Allow2Response.Error( Allow2Error.InvalidResponse ))
                    return;
                }
                
                let result = Allow2Response.parseFromJSON(response: json)
                
                switch result {
                case let .CheckResult(checkResult):
                    
                    // good response, cache the result first
                    self.resultCache[key] = checkResult
                    
                    // notify everyone
                    NotificationCenter.default.post(
                        name: .allow2CheckResultNotification,
                        object: nil,
                        userInfo: [ "result" : checkResult ]
                    )
                    
                    break
                default:
                    completion?(result)
                    return
                }
                
                // now return the result
                completion?(result)
            }
            task.resume()
            
        } catch (let err) {
            print(err)
            completion?(Allow2Response.Error( err ))
        }
    }
}
