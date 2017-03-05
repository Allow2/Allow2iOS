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
}

/**
 *  Error Types
 */
public enum Allow2Error: ErrorType {
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
    case Error(ErrorType)
    case PairResult(Allow2PairResult)
    case CheckResult(Allow2CheckResult)
    
    static func parseFromJSON(response : JSON) -> Allow2Response {
        guard response["error"] != "invalid pairId" else {
            // special case, no longer controlled
            Allow2.shared.userId = nil
            Allow2.shared.pairId = nil
            Allow2.shared.childId = nil
            Allow2.shared.children = []
            return .CheckResult(Allow2CheckResult(
                allowed: true,
                activities: [],
                dayTypes: []
                ))
        }
        
        guard let allowed = response["allowed"].bool else {
            return .Error(Allow2Error.InvalidResponse)
        }
        let activities = response["activities"]
        let dayTypes = response["dayTypes"]
        
        return .CheckResult(Allow2CheckResult(
            allowed: allowed,
            activities: activities,
            dayTypes: dayTypes
            ))
    }
}


public class Allow2 {

    public var deviceToken : String? = "Not Set";

    var userId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2UserId") as? String) } // ?? "6"
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2UserId") }
    }
    var pairId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2PairId") as? String) } // ?? "18956"
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2PairId") }
    }
    
    public var isPaired : Bool {
        get {
            return (self.userId != nil) && (self.pairId != nil)
        }
    }

    public var children : [ Allow2Child ] = [] // todo: maintain this automatically
    
    // used only if the device is locked to a specific user.
    public var childId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2ChildId") as? String) } // ?? "68"
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2ChildId") }
    }
    
    public static let PairingChangedNotification = "Allow2PairingChangedNotification"
    public static let CheckResultNotification = "Allow2CheckResultNotification"
    
    // todo: should do this better
    public static var allow2BlockViewController : Allow2BlockViewController {
        get {
            let allow2FrameworkBundle = NSBundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewControllerWithIdentifier("Allow2BlockViewController") as! Allow2BlockViewController
        }
    }

    // todo: should do this better
    public static var allow2PairingViewController : Allow2PairingViewController {
        get {
            let allow2FrameworkBundle = NSBundle(identifier: "com.allow2.Allow2Framework")
            let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
            return storyboard.instantiateViewControllerWithIdentifier("Allow2PairingViewController") as! Allow2PairingViewController
        }
    }

    
    public static var AllowLogo : UIImage {
        get {
            return UIImage(named: "Allow2 Logo", inBundle: NSBundle(forClass: Allow2.self), compatibleWithTraitCollection: nil)!
        }
    }
    
    let appUrl = "https://api.allow2.com:8443"
    let apiUrl = "https://api.allow2.com:9443"
    
    public static let shared = Allow2()
    
    private init (){
        //print("Allow2 has been initialised")
    }
    
    /**
     * cached responses (each expire as required)
     * 
     * Simplistic initial implementation uses the full hashed request as the key, probably should cache more intelligently in future
     */
    var resultCache : [ String : Allow2CheckResult! ] = [ : ]
    

    /**
     * Activity descriptor to pass to the check call
     */
    public class Allow2Activity {
        
        var jsonObject : [ String : AnyObject! ]
        
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
        
        let url = NSURL(string: "\(appUrl)/api/pairDevice")
        
        let body : JSON = [
            "user": user,
            "pass": password,
            "deviceToken": self.deviceToken ?? "MISSING",
            "name": deviceName
        ];
        
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        //json: true,
        
        do {
            request.HTTPBody = try body.rawData()
            
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {(data, response, error) in
                print(NSString(data: data!, encoding: NSUTF8StringEncoding))
                
                let json = JSON(data: data!)
                
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
                            newChildren.append(Allow2Child(id: child["id"].uInt64Value, name: child["name"].stringValue))
                        }
                        self.children = newChildren
                        
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
        check(self.childId ?? "68", activities: activities, log: log, completion: completion)
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
        
        let body : JSON = [
            "userId": self.userId!,
            "pairId": self.pairId!,
            "deviceToken": self.deviceToken ?? "MISSING",
            "childId": childId,
            "tz": NSTimeZone.localTimeZone().name,
            "activities": activities.jsonArray,
            "log": log
        ];
        let key = body.rawString()!
        
        // check the cache first
        if let checkResult = self.resultCache[key] {
            
            if !checkResult.expires.timeIntervalSinceNow.isSignMinus {
                // not expired yet, use cached value
                if completion != nil {
                    completion!( Allow2Response.CheckResult(checkResult) )
                }
                return
            }
            
            // clear cached value and ask the server again
            self.resultCache.removeValueForKey(key)
        }
        
        let url = NSURL(string: "\(apiUrl)/serviceapi/check")
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        //json: true,
        
        do {
            request.HTTPBody = try body.rawData()
        
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {(data, response, error) in
                guard error == nil else {
                    completion?(Allow2Response.Error( error! ))
                    return;
                }
                
                guard data != nil else {
                    completion?(Allow2Response.Error( Allow2Error.InvalidResponse ))
                    return;
                }
                
                print(NSString(data: data!, encoding: NSUTF8StringEncoding))
                
                // interpret the result
                // todo: 403 is disconnected, clear everything out
                
                // handle other errors
                
                // attempt to handle valid response
                let result = Allow2Response.parseFromJSON(JSON(data: data!))
                
                switch result {
                case let .CheckResult(checkResult):
                    
                    // good response, cache the result first
                    self.resultCache[key] = checkResult

                    // notify everyone
                    NSNotificationCenter.defaultCenter().postNotificationName(
                        Allow2.CheckResultNotification,
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
    var jsonArray : [[String : AnyObject!]] {
        get {
            return self.map() {
                return $0.jsonObject
            }
        }
    }
}
