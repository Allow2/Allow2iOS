//
//  Allow2.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 6/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import Foundation

public class Allow2 {
    
    var userId : String? = ""
    var pairId : String? = ""
    var deviceToken : String? = ""
    var childId : String? = ""
    
    let apiUrl = "https://api.allow2.com/"
    
    public class Allow2Activity {
        
        var jsonObject : [ String : AnyObject! ]

        init(id: Int, log: Bool = true) {
            jsonObject = [
                "id": id,
                "log": log
            ]
        }
    }
    
    public static let sharedInstance = Allow2()
    
    private init (){
        //print("Allow2 has been initialised")
    }
    
    public func pair(user : String!, password: String!, deviceName : String!, completion: (() -> Void)? = nil) {
        let url = NSURL(string: "\(apiUrl)/api/pairDevice")
        
        let body : JSON = [
            "user": user,
            "pass": password,
            "deviceToken": "fkptV9fm4OCbhGv6",
            "name": deviceName
        ];
        
        let request = NSMutableURLRequest(URL: url!)
        request.HTTPMethod = "POST";
        //json: true,
        
        do {
            request.HTTPBody = try body.rawData()
            
            let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {(data, response, error) in
                print(NSString(data: data!, encoding: NSUTF8StringEncoding))
            }
            task.resume()
            
        } catch (let err) {
            print(err)
        }
    }
    
    public func check(activities: [Allow2Activity], log: Bool = true, completion: (() -> Void)? = nil) {
        let url = NSURL(string: "\(apiUrl)/serviceapi/check")

        let body : JSON = [
            "userId": self.userId!,
            "pairId": self.pairId!,
            "deviceToken": self.deviceToken!,
            "childId": self.childId!,
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
            }
            task.resume()
            
        } catch (let err) {
            print(err)
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
