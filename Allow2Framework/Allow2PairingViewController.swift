//
//  Allow2PairingViewController.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 5/3/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

public protocol Allow2PairingViewControllerDelegate {
    func Allow2PairingCompleted(result: Allow2Response)
}

public class Allow2PairingViewController: UITableViewController {
    
    public var delegate : Allow2PairingViewControllerDelegate?
    
    private var checkResult : Allow2CheckResult?
    @IBOutlet var deviceNameField : UITextField?
    @IBOutlet var barcodeImageView : UIImageView?
    @IBOutlet var usernameField : UITextField?
    @IBOutlet var passwordField : UITextField?
    @IBOutlet var connectButton : UIButton?
    
    var pollingTimer: Timer!
    var bluetooth = Allow2Bluetooth()
    
    let qrQueue = DispatchQueue(label: "Allow2QRGenerationQueue")
    
    var _deviceName : String! = UIDevice.current.name
    var deviceName : String! {
        get {
            return _deviceName
        }
        set {
            _deviceName = newValue
            deviceNameField?.text = _deviceName
            updateBarcode()
        }
    }
    
    // todo: is a factory method better?
    public static func instantiate() -> Allow2PairingViewController? {
        if Allow2.shared.pairId != nil {
            // don't allow re-pairing if we are already paired!
            return nil
        }
        let allow2FrameworkBundle = Bundle(identifier: "com.allow2.Allow2Framework")
        let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: allow2FrameworkBundle)
        return storyboard.instantiateViewController(withIdentifier: "Allow2PairingViewController") as? Allow2PairingViewController
    }
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !Allow2.shared.isPaired else {
            self.delegate?.Allow2PairingCompleted(result: Allow2Response.Error( Allow2Error.AlreadyPaired ))
            return
        }

        deviceNameField?.text = deviceName
        updateBarcode()
        
        bluetooth.startAdvertising()

        self.pollingTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(Allow2PairingViewController.pollPairing), userInfo: nil, repeats: true)
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.pollingTimer.invalidate()
        self.pollingTimer = nil
        bluetooth.stopAdvertising()

    }
    
    func updateBarcode() {
        //if let name = deviceNameField?.text?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
        let hasName = (deviceName.characters.count > 0)
        if hasName {
            barcodeImageView?.isHidden = false
            qrQueue.async() {
                let newQR = Allow2.shared.generateQRImage(name: self.deviceName, withSize: CGSize(width: 120, height: 120))
                DispatchQueue.main.async() {
                    self.barcodeImageView?.image = newQR
                }
            }
        } else {
            barcodeImageView?.isHidden = true
            barcodeImageView?.image = nil
        }
        let username = usernameField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField?.text ?? ""
        // todo: better sanity checks
        connectButton?.isEnabled = hasName && (username.characters.count > 4) && (password.characters.count > 4)
    }
    
    @IBAction func connect() {
        let user = usernameField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField?.text ?? ""

        guard (user.characters.count > 0) && (password.characters.count > 0) && (deviceName.characters.count > 0) else {
            print("Cancelled")
            return
        }
        
        UIApplication.shared.beginIgnoringInteractionEvents()
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        Allow2.shared.pair(user: user, password: password, deviceName: deviceName) { (result) in
            UIApplication.shared.endIgnoringInteractionEvents()
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            switch result {
            case .PairResult(let pairResult):
                print("paired")
                //self.selectChild(result.children)
                self.delegate?.Allow2PairingCompleted(result: result)
                break
            case .Error(let error):
                self.delegate?.Allow2PairingCompleted(result: result)
                return
            default:
                break // cannot happen
            }
        }
    }
}

extension Allow2PairingViewController : UITextFieldDelegate {
    
    @IBAction func textFieldEdited(sender: UITextField) {
        let newDeviceName = sender.text?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if newDeviceName != self.deviceName {
            self.deviceName = newDeviceName
        }
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if (textField == self.deviceNameField) {
            textField.resignFirstResponder()
            return true
        }
        if (textField == self.usernameField) {
            self.passwordField?.becomeFirstResponder()
            return true
        }
        if (textField == self.passwordField) {
            textField.resignFirstResponder()
            connect()
            return true
        }
        return true
    }
}

extension Allow2PairingViewController {
    @objc func pollPairing() {
        let url = URL(string: "\(Allow2.shared.appUrl)/api/checkPairing")
        
        let body : JSON = [
            "uuid": UIDevice.current.identifierForVendor!.uuidString,
            "deviceToken": Allow2.shared.deviceToken ?? "MISSING"
        ];
        
        var request = URLRequest(url: url!)
        request.httpMethod = "POST";
        request.addValue("application/json", forHTTPHeaderField:"Content-Type")
        
        do {
            request.httpBody = try body.rawData()
            
            let task = URLSession.shared.dataTask(with: request) {(data, response, error) in
                
                guard error == nil else {
                    return
                }
                
                // anything other than a 200 response is a "try again" as far as we are concerned
                let status = (response as! HTTPURLResponse).statusCode
                if status != 200 {
                    return
                }
                
                print(NSString(data: data!, encoding: String.Encoding.utf8.rawValue)!)
                
                // todo: better error handling on data -> JSON
                let json = try! JSON(data: data!)
                
                if let status = json["status"].string {
                    
                    guard status == "success" else {
                        self.delegate?.Allow2PairingCompleted(result: Allow2Response.Error(Allow2Error.Other(message: json["message"].string ?? "Unknown Error" )))
                        return
                    }
                    
                    Allow2.shared.pairId = "\(json["pairId"].uInt64Value)"
                    Allow2.shared.userId = "\(json["userId"].uInt64Value)"
                    if let childId = json["childId"].uInt64 {
                        Allow2.shared.childId = "\(childId)"
                        Allow2.shared.children = []
                        self.delegate?.Allow2PairingCompleted(result: Allow2Response.PairResult(Allow2PairResult( children: [] )))
                        return
                    }
                    
                    // no child selected by the parent when pairing
                    // todo: maintain the list of children internally
                    let childrenJson = json["children"].array ?? []
                    var newChildren : [Allow2Child] = []
                    for child in childrenJson {
                        newChildren.append(Allow2Child(id: child["id"].uInt64Value, name: child["name"].stringValue))
                    }
                    Allow2.shared.children = newChildren
                    self.delegate?.Allow2PairingCompleted(result: Allow2Response.PairResult(Allow2PairResult( children: Allow2.shared.children )))
                }
            }
            task.resume()
            
        } catch (let err) {
            print(err)
        }
    }
}
