//
//  Allow2CheckResult.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 8/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import Foundation

/**
 * Result from a successful check call
 */
public class Allow2CheckResult {
    var _allowed : Bool
    var _activities : JSON
    var _children : JSON
    var _today : Allow2Day
    var _tomorrow : Allow2Day
    
    var expires: NSDate {
        get {
            return NSDate(timeIntervalSince1970: activities["0"]["expires"].double ?? 0.0)
        }
    }
    
    public init(allowed: Bool,
                 activities: JSON,
                 dayTypes: JSON,
                 children: JSON) {
        self._allowed = allowed
        self._activities = activities
        self._children = children
        self._today = Allow2Day(json: dayTypes["today"])
        self._tomorrow = Allow2Day(json: dayTypes["tomorrow"])
    }
}

func dateFromISOString(string: String) -> Date? {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone.autoupdatingCurrent
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    
    return dateFormatter.date(from: string)
}

/**
 * Getters
 */
extension Allow2CheckResult {

    public var allowed : Bool { get { return _allowed } }
    public var activities : JSON { get { return _activities } }
    public var today : Allow2Day { get { return _today } }
    public var tomorrow : Allow2Day { get { return _tomorrow } }

    public var explanation : String {
        get {
            var reasons : [String] = [];
            if (!allowed) {
                // todo: reasons.append() ?
            }
            activities.forEach { (s, activity) in
                if activity.dictionary?["banned"]?.boolValue ?? false {
                    reasons.append("You are currently banned from \(activity["name"]).")
                } else if !(activity.dictionary?["timeblock"]?.dictionary?["allowed"]?.boolValue ?? true) {
                    reasons.append("You cannot use \(activity["name"]) at this time.")
                } else {
                    // todo: reasons.append("You have \(activity["remaining"]) to use \(activity["name"]).")
                }
            }
            return reasons.joined(separator: "/n");
        }
    }
    
    
    
    public var currentBans : [[String : Any]]! {
        get {
            var bans : [[ String : Any ]] = [];
            activities.forEach { (s, activity) in
                if activity.dictionary?["banned"]?.boolValue ?? false,
                    let id = activity.dictionary?["id"]?.uInt64Value,
                    let name = activity.dictionary?["name"]?.stringValue,
                    let items = activity.dictionary?["bans"]?.dictionary?["bans"]?.array {
                    items.forEach { (item) in
                        bans.append([
                            "id" : id,
                            "title": name,
                            "appliedAt" : dateFromISOString(string: item["appliedAt"].stringValue) as Any,
                            "duration" : item["durationMinutes"].intValue,
                            "selected": false
                            ])
                    }
                } else {
                    // todo: reasons.append("You have \(activity["remaining"]) to use \(activity["name"]).")
                }
            }
            return bans
        }
    }
}

/**
 * Utility Class
 */
public class Allow2Day {
    var _id : Int64
    var _name : String
    public var name : String { get { return _name } }
    
    init(json: JSON) {
        _id = json["id"].int64 ?? 0
        _name = json["name"].string ?? ""
    }
}
