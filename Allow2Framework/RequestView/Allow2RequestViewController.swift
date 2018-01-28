//
//  Allow2BlockView.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 7/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

public protocol Allow2RequestViewControllerDelegate {
    
}

public class Allow2RequestViewController: UITableViewController {
    
    var delegate : Allow2RequestViewControllerDelegate?
    var newDayType : Int64? = nil;
    private var currentBans = [[String: Any]]()
    var checkResult : Allow2CheckResult? {
        didSet {
            //checkResult.bans.bans.each
            //self.checkResult
            //activities.dictionary?["1"]?.dictionary?["bans"]?.dictionary?["bans"]
            newDayType = nil
            //currentBans = checkResult
            currentBans.append(["id" : 1, "Title": "Internet Ban", "selected": false])
            currentBans.append(["id" : 2, "Title": "Gaming Ban", "selected": false])
        }
    }
    var message : String? = nil

    @IBAction func Cancel() {
        self.presentingViewController?.dismiss(animated: true)
    }
    
    @IBAction func Send() {
        self.presentingViewController?.dismiss(animated: true)
    }
    
}


// MARK:- DataSource

extension Allow2RequestViewController {
    
    override public func numberOfSections(in tableView: UITableView) -> Int {
        return 2 + ( currentBans.count > 0 ? 1 : 0 )
    }
    
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        }
        if section >= self.numberOfSections(in: tableView) - 1 {
            return 1
        }
        return currentBans.count
    }

    override public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Change Day Type:"
        }
        if section >= self.numberOfSections(in: tableView) - 1 {
            return "Message:"
        }
        
        return "Lift Ban:"
    }
    
    
    override public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section < self.numberOfSections(in: tableView) - 1
    }
    
    func formatBanCell(_ cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let ban = self.currentBans[indexPath.row]
        cell.textLabel?.text = ban["Title"] as? String
        cell.accessoryType = ban["selected"] as? Bool ?? false ? .checkmark : .none
    }
    
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayTypeCell")!
            cell.textLabel?.text = "School Day"
            return cell
        }
        if indexPath.section >= self.numberOfSections(in: tableView) - 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell") as! MessageCell
            cell.messageField?.text = self.message
            return cell
        }
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "BanCell")!
        formatBanCell(cell, forRowAt: indexPath)
        return cell
    }
}


// MARK:- Delegate

extension Allow2RequestViewController {
    
    override public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        print(indexPath)
        if indexPath.section == 0 {
            
            tableView.deselectRow(at: indexPath, animated: true)
            return
        }
        if indexPath.section >= self.numberOfSections(in: tableView) - 1 {
            tableView.deselectRow(at: indexPath, animated: false)
            self.currentBans[indexPath.row]["selected"] = !(self.currentBans[indexPath.row]["selected"] as? Bool ?? false)
            formatBanCell(self.tableView(tableView, cellForRowAt: indexPath), forRowAt: indexPath)
            return
        }
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
}
