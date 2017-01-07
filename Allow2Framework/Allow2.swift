//
//  Allow2.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 6/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import Foundation

public class Allow2 {
    
    var userId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2UserId") as? String) ?? "6" } // todo: return nil
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2UserId") }
    }
    var pairId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2PairId") as? String) ?? "18956" } // todo: return nil
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2PairId") }
    }
    // used only if the device is locked to a specific user.
    var childId : String? {
        get { return (NSUserDefaults.standardUserDefaults().objectForKey("Allow2ChildId") as? String) ?? "68" } // todo: return nil
        set { NSUserDefaults.standardUserDefaults().setObject(newValue, forKey: "Allow2ChildId") }
    }
    
    public static let PairingChangedNotification = "Allow2PairingChangedNotification"
    
    let apiUrl = "https://api.allow2.com:8443"
    let deviceToken = "fkptV9fm4OCbhGv6"
    
    public static let sharedInstance = Allow2()
    
    private init (){
        //print("Allow2 has been initialised")
    }
    
    /**
     * cached responses (each expire as required)
     * 
     * Simplistic initial implementation uses the full hashed request as the key, probably should cache more intelligently in future
     */
    var resultCache : [ String : Allow2Response! ] = [ : ]
    

    /**
     * Activity descriptor to pass to the check call
     */
    public class Allow2Activity {
        
        var jsonObject : [ String : AnyObject! ]
        
        init(id: Int, log: Bool = true) {
            jsonObject = [
                "id": id,
                "log": log
            ]
        }
    }
    
    /**
     *  Error Types
     */
    enum Allow2Error: ErrorType {
        case NotPaired
        case AlreadyPaired
        case MissingChildId
        case NotAuthorised
    }
    
    /**
     * Response from the check call
     */
    public enum Allow2Response {
        case Error(ErrorType)
        case PairResult(Allow2PairResult)
        case CheckResult(Allow2CheckResult)
    }

    /**
     * Result from a successful check call
     */
    public struct Allow2PairResult {
        var Children : [ String ]
    }
    
    /**
     * Result from a successful check call
     */
    public struct Allow2CheckResult {
        var allowed : Bool
        var description : String?
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
        
        guard (self.userId == nil) && (self.pairId == nil) else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.AlreadyPaired ))
            }
            return
        }
        
        let url = NSURL(string: "\(apiUrl)/api/pairDevice")
        
        let body : JSON = [
            "user": user,
            "pass": password,
            "deviceToken": self.deviceToken,
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
                if (completion != nil) {
                    completion!(Allow2Response.PairResult(Allow2PairResult(
                        Children: []
                        )))
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
        guard self.childId != nil else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.MissingChildId ))
            }
            return
        }
        check(self.childId!, activities: activities, log: log, completion: completion)
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
        
        guard (self.userId != nil) && (self.pairId != nil) else {
            if completion != nil {
                completion!(Allow2Response.Error( Allow2Error.NotPaired ))
            }
            return
        }
        
        // check the cache first
        if (false) {
            // use cached value
            return
        }
        
        let url = NSURL(string: "\(apiUrl)/serviceapi/check")

        let body : JSON = [
            "userId": self.userId!,
            "pairId": self.pairId!,
            "deviceToken": self.deviceToken,
            "childId": childId,
            "tz": NSTimeZone.localTimeZone().name,
            "activities": activities.jsonArray,
            "log": log
        ];
        
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "POST";
        //json: true,
        
        do {
            request.HTTPBody = try body.rawData()
        
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {(data, response, error) in
                print(NSString(data: data!, encoding: NSUTF8StringEncoding))
                // cache the result first
                
                // now return the result
                if completion != nil {
                    completion!(Allow2Response.CheckResult(Allow2CheckResult(
                        allowed: true,
                        description: nil
                        )))
                }
            }
            task.resume()
            
        } catch (let err) {
            print(err)
            if completion != nil {
                completion!(Allow2Response.Error( err ))
            }
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
