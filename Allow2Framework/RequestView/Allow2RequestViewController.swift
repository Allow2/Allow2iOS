//
//  Allow2BlockView.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 7/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit
import SVProgressHUD

public protocol Allow2RequestViewControllerDelegate {
    
}

public class Allow2RequestViewController: UITableViewController {
    
    var delegate : Allow2RequestViewControllerDelegate?
    var newDayType : Allow2Day = Allow2Day(id: 0, name: "Do Not Change")
    private var currentBans = [[String: Any]]()
    private var dayType : Allow2Day?
    private var dayTypes : [ Allow2Day ]?
    private var needSubscription : Bool = false
    var checkResult : Allow2CheckResult? {
        didSet {
            needSubscription = checkResult?.needSubscription != nil
            subscriptionSection = needSubscription ? 0 : nil
            dayTypeSection = subscriptionSection != nil ? 1 : 0
            newDayType = Allow2Day(id: 0, name: "Do Not Change");
            currentBans = checkResult?.currentBans ?? [[String: Any]]()
            banSection = currentBans.count > 0 ? dayTypeSection + 1 : nil
            dayTypes = checkResult?.allDayTypes.array?.map({ (json) -> Allow2Day in
                return Allow2Day(json: json)
            }) ?? []
        }
    }
    var message : String? = nil
    var pickerShown = false
    
    var subscriptionSection : Int?
    var dayTypeSection : Int = 0
    var banSection : Int?
    
    @IBOutlet var sendButton : UIBarButtonItem?
    @IBAction func Cancel() {
        self.presentingViewController?.dismiss(animated: true)
    }
    
    @IBAction func Send() {
        // warning: remember what had focus and restore it to that element on failure
        if (!shouldEnableSend()) {
            return
        }
        self.resignFirstResponder()
        let dayTypeId = self.newDayType._id > 0 ? self.newDayType._id : nil
        let lift : [ UInt64 ] = self.currentBans.filter({ (ban) -> Bool in
            return ban["selected"] as? Bool ?? false
        }).map { (ban) -> UInt64 in
            return ban["id"] as! UInt64
        }
        print("newDayType: \(String(describing: dayTypeId)), lift: \(lift), message: \(String(describing: self.message))")
        SVProgressHUD.show(withStatus: "Sending Request...")
        UIApplication.shared.beginIgnoringInteractionEvents()
        Allow2.shared.request(dayTypeId: dayTypeId, lift: lift.count > 0 ? lift : nil, message: self.message) { response in
            print("\(response)")
            DispatchQueue.main.async {
                UIApplication.shared.endIgnoringInteractionEvents()
                switch (response) {
                case let .Request(requestSent):
                    if !requestSent {
                        SVProgressHUD.showError(withStatus: "Unable to Send")
                        return
                    }
                    SVProgressHUD.showSuccess(withStatus: "Request Sent")
                    self.presentingViewController?.dismiss(animated: true)
                case let .Error(err):
                    // warning: show a suitable error somehow
                    SVProgressHUD.showError(withStatus: err.localizedDescription)
                    print("\(err)")
                    return
                default:
                    return
                }
            }
        }
    }
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        enableSendButton()
        SVProgressHUD.setDefaultStyle(.custom)
        SVProgressHUD.setForegroundColor(.allow2Gold)
        SVProgressHUD.setBackgroundColor(.allow2DarkGray)
    }
    
    func shouldEnableSend() -> Bool {
        if needSubscription { return true }
        let atLeastOneBan = currentBans.reduce(false) { (result, ban) -> Bool in
            return result || ban["selected"] as? Bool ?? false
        }
        return atLeastOneBan || (newDayType._id != 0)
    }
    
    func enableSendButton() {
        DispatchQueue.main.async {
            self.sendButton?.isEnabled = self.shouldEnableSend()
        }
    }
}


// MARK:- DataSource

extension Allow2RequestViewController {
    
    override public func numberOfSections(in tableView: UITableView) -> Int {
        return 2 + (needSubscription ? 1 : 0) + (currentBans.count > 0 ? 1 : 0)
    }
    
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == subscriptionSection {
            return 1
        }
        if section == dayTypeSection {
            return 2
        }
        if section >= self.numberOfSections(in: tableView) - 1 {
            return 1
        }
        return currentBans.count
    }

    override public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == subscriptionSection {
            return "Subscription Needed"
        }
        if section == dayTypeSection {
            return "Change Day Type"
        }
        if section >= self.numberOfSections(in: tableView) - 1 {
            return "Message"
        }
        
        return "Lift Ban"
    }
    
    override public func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if (indexPath.section == dayTypeSection) && (indexPath.row == 1) && !pickerShown {
            return 0
        }
        return super.tableView(tableView, heightForRowAt: indexPath)
    }
    
    override public func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section == subscriptionSection { return false }
        return indexPath.section < self.numberOfSections(in: tableView) - 1
    }
    
    func formatBanCell(_ cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let ban = self.currentBans[indexPath.row]
        cell.textLabel?.text = ban["title"] as? String
        cell.detailTextLabel?.text = "\(Double(ban["duration"] as! Int) / 60.0)"
        cell.accessoryType = ban["selected"] as? Bool ?? false ? .checkmark : .none
    }
    
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == subscriptionSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayTypeCell")!
            cell.textLabel?.text = "Allow2 needs an active subscription"
            cell.accessoryType = .checkmark
            return cell
        }
        if indexPath.section == dayTypeSection {
            if indexPath.row == 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: "DayTypeCell")!
                cell.textLabel?.text = self.newDayType.name
                return cell
            }
            let cell = tableView.dequeueReusableCell(withIdentifier: "DayTypePickerCell") as! DayTypePickerCell
            cell.delegate = self
            cell.dayTypes = self.dayTypes
            return cell
        }
        if indexPath.section >= self.numberOfSections(in: tableView) - 1 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell") as! MessageCell
            cell.messageField?.text = self.message
            cell.messageField?.delegate = self
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
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == subscriptionSection {
            return
        }
        if indexPath.section == dayTypeSection {
            if indexPath.row == 0 {
                pickerShown = !pickerShown
                tableView.beginUpdates()
                tableView.endUpdates()
            }
            return
        }
        if indexPath.section < self.numberOfSections(in: tableView) - 1 {
            self.currentBans[indexPath.row]["selected"] = !(self.currentBans[indexPath.row]["selected"] as? Bool ?? false)
            //formatBanCell(self.tableView(tableView, cellForRowAt: indexPath), forRowAt: indexPath)
            tableView.beginUpdates()
            tableView.reloadRows(at: [indexPath], with: .fade)
            tableView.endUpdates()
            self.enableSendButton()
            return
        }
        
        let cell = self.tableView(tableView, cellForRowAt: indexPath) as! MessageCell
        cell.messageField?.becomeFirstResponder()
    }
    
}

extension Allow2RequestViewController : UITextFieldDelegate {
    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if !shouldEnableSend() {
            return false
        }
        self.Send()
        return true
    }
    
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let oldText = textField.text!
        let newText = oldText.replacingCharacters(in: Range(range, in: oldText)!, with: string)
        let message = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        self.message = message.lengthOfBytes(using: .utf8) > 0 ? message : nil
        return true
    }
}

extension Allow2RequestViewController : DayTypePickerCellDelegate {
    func dayTypePickerCell(_ cell: DayTypePickerCell, didChooseDayType dayType: Allow2Day) {
        self.newDayType = dayType
        DispatchQueue.main.async {
            self.tableView.beginUpdates()
            self.tableView.reloadRows(at: [IndexPath(row: 0, section: self.dayTypeSection)], with: .fade)
            self.tableView.endUpdates()
            self.enableSendButton()
        }
    }
}
