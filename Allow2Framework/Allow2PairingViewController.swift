//
//  Allow2PairingViewController.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 5/3/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit
import StoreKit
import SVProgressHUD

public protocol Allow2PairingViewControllerDelegate {
    func Allow2PairingCompleted(result: Allow2Response)
}

public class Allow2PairingViewController: UIViewController {
    
    public var delegate : Allow2PairingViewControllerDelegate?
    
    private var checkResult : Allow2CheckResult?
    @IBOutlet var deviceNameField : UITextField?
    @IBOutlet var barcodeImageView : UIImageView?
    @IBOutlet var usernameField : UITextField?
    @IBOutlet var passwordField : UITextField?
    @IBOutlet var connectButton : UIButton?
    @IBOutlet var activityIndicator : UIActivityIndicatorView?
    @IBOutlet var generatingLabel : UILabel?
    @IBOutlet var generateButton : UIButton?
    
    @IBOutlet var scanView : UIView?
    @IBOutlet var manualView : UIView?
    @IBOutlet var orConnectManuallyButton : UIButton?
    @IBOutlet var orScanButton : UIButton?
    
    var pollingTimer: Timer!
    var bluetooth = Allow2Bluetooth()
    
    let qrQueue = DispatchQueue(label: "Allow2QRGenerationQueue")
 
    var username : String! = ""
    var password : String! = ""

    var _deviceName : String! = UIDevice.current.name
    var deviceName : String! {
        get {
            return _deviceName
        }
        set {
            _deviceName = newValue
            deviceNameField?.text = _deviceName
        }
    }
    
    var barcodeUpdateDebouncer = Debouncer(delay: 0.4) {
    };
    
    // todo: is a factory method better?
    public static func instantiate() -> Allow2PairingViewController? {
        if Allow2.shared.pairId != nil {
            // don't allow re-pairing if we are already paired!
            return nil
        }
        let storyboard = UIStoryboard(name: "Allow2Storyboard", bundle: Allow2.bundle)
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
        
        barcodeUpdateDebouncer = Debouncer(delay: 0.4) {
            DispatchQueue.main.async {
                self.updateBarcode();
            }
        };
        
        bluetooth.startAdvertising()

        self.pollingTimer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(Allow2PairingViewController.pollPairing), userInfo: nil, repeats: true)
        self.navigationItem.title = "Parental Freedom"
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.pollingTimer.invalidate()
        self.pollingTimer = nil
        barcodeUpdateDebouncer.timer?.invalidate()
        bluetooth.stopAdvertising()
    }
    
    func enableLogin() {
        let hasName = (deviceName.count > 0)
        // todo: better sanity checks
        DispatchQueue.main.async() {
            self.connectButton?.isEnabled = hasName && (self.username.count > 4) && (self.password.count > 4)
        }
    }
    
    func updateBarcode() {
        activityIndicator?.startAnimating()
        generatingLabel?.isHidden = false
        generateButton?.isHidden = true
        let size = CGSize(width: self.barcodeImageView!.frame.width, height: self.barcodeImageView!.frame.height)
        DispatchQueue.global(qos: .background).async() {
            let newQR = Allow2.shared.generateQRImage(name: self.deviceName, withSize: size)
            DispatchQueue.main.async() {
                self.barcodeImageView?.image = newQR
                self.activityIndicator?.stopAnimating()
                self.generatingLabel?.isHidden = true
            }
        }
        enableLogin()
    }
    
    @IBAction func connect() {
        let user = usernameField?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField?.text ?? ""

        guard (user.count > 0) && (password.count > 0) && (deviceName.count > 0) else {
            print("Cancelled")
            return
        }
        
        UIApplication.shared.beginIgnoringInteractionEvents()
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        SVProgressHUD.show(withStatus: "Contacting Allow2")
        Allow2.shared.pair(user: user, password: password, deviceName: deviceName) { (result) in
            DispatchQueue.main.async {
                UIApplication.shared.endIgnoringInteractionEvents()
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
            switch result {
            case .PairResult(let pairResult):
                print("paired \(pairResult)")
                //self.selectChild(result.children)
                DispatchQueue.main.async {
                    SVProgressHUD.showSuccess(withStatus: "Connected")
                }
                self.delegate?.Allow2PairingCompleted(result: result)
                break
            case .Error(let error):
                print("pair error \(error)")
                DispatchQueue.main.async {
                    SVProgressHUD.showError(withStatus: error.localizedDescription)
                }
                self.delegate?.Allow2PairingCompleted(result: result)
                return
            default:
                DispatchQueue.main.async {
                    SVProgressHUD.showError(withStatus: "Unknown Error")
                }
                break // cannot happen
            }
        }
    }
    
    @IBAction func scanMode() {
        setScanMode(scan: true)
    }
    
    @IBAction func manualMode() {
        setScanMode(scan: false)
    }
    
    func setScanMode(scan : Bool) {
        orScanButton?.isHidden = scan
        orConnectManuallyButton?.isHidden = !scan
        scanView?.isHidden = !scan
        manualView?.isHidden = scan
        let editingDeviceName = self.deviceNameField?.isFirstResponder == true
        let editingUsername = self.usernameField?.isFirstResponder == true
        let editingPassword = self.passwordField?.isFirstResponder == true
        if scan {
            if editingUsername {
                self.usernameField?.resignFirstResponder()
                return
            }
            if editingPassword {
                self.passwordField?.resignFirstResponder()
                return
            }
        } else if !editingDeviceName {
            if self.usernameField?.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 < 1 {
                self.usernameField?.becomeFirstResponder()
                return
            }
            if self.passwordField?.text?.count ?? 0 < 1 {
                self.passwordField?.becomeFirstResponder()
                return
            }
        }
    }
    
    @IBAction func getAllow2() {
        //if let URL = https://geo.itunes.apple.com/us/app/allow2/id569486440?mt=12
        let storeProductVC = SKStoreProductViewController()
        storeProductVC.delegate = self
        storeProductVC.loadProduct(withParameters: [
            SKStoreProductParameterITunesItemIdentifier : "569486440",
            SKStoreProductParameterCampaignToken: "Allow2iOSApp"
        ]) { (success, err) in
//            if let err = err {
//                SVProgressHUD.showError(withStatus: err.localizedDescription)
//            }

            storeProductVC.presentingViewController?.dismiss(animated: true)
        }
        
        // present right away to avoid pause
        self.present(storeProductVC, animated:true, completion:nil)
        //UIApplication.shared.delegate?.window??.rootViewController?.present(storeProductVC, animated:true, completion:nil)
    }
}

extension Allow2PairingViewController : UITextFieldDelegate {
        
    public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text,
            let textRange = Range(range, in: text) else {
            return true
        }
        
        let updatedText = text.replacingCharacters(in: textRange, with: string)
    
        guard textField != self.deviceNameField else {
            let trimmed = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if updatedText != self.deviceName {
                self._deviceName = trimmed
                barcodeUpdateDebouncer.call()
            }
            enableLogin()
            return true
        }
        if textField == self.usernameField {
            self.username = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if textField == self.passwordField {
            self.password = updatedText
        }
        enableLogin()
        return true
    }

    public func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == self.deviceNameField {
            textField.resignFirstResponder()
            // todo: if self.manualView is visible, we can allow the "next" function to go to the username field (tab through)
            return true
        }
        if textField == self.usernameField {
            self.passwordField?.becomeFirstResponder()
            return true
        }
        if textField == self.passwordField {
            textField.resignFirstResponder()
            if connectButton?.isEnabled ?? false {
                connect()
            }
            return true
        }
        return true
    }
    
    @IBAction func dismissKeyboard() {
        if (self.deviceNameField?.isFirstResponder ?? false) {
            self.deviceNameField?.resignFirstResponder()
            return
        }
        if (self.usernameField?.isFirstResponder ?? false) {
            self.usernameField?.resignFirstResponder()
            return
        }
        if (self.passwordField?.isFirstResponder ?? false) {
            self.passwordField?.resignFirstResponder()
            return
        }
    }
}

extension Allow2PairingViewController {
    @objc func pollPairing() {
        let url = URL(string: "\(Allow2.shared.apiUrl)/api/checkPairing")
        
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
                    // this only comes back if the server is forcing the device to be locked to a specific child
                    if let childId = json["childId"].uInt64 {
                        Allow2.shared.childId = "\(childId)"
                        Allow2.shared._children = []
                        self.delegate?.Allow2PairingCompleted(result: Allow2Response.PairResult(Allow2PairResult( children: [] )))
                        return
                    }
                    
                    // no child selected by the parent when pairing
                    // todo: maintain the list of children internally
                    let childrenJson = json["children"].array ?? []
                    var newChildren : [Allow2Child] = []
                    for child in childrenJson {
                        newChildren.append(Allow2Child(id: child["id"].uInt64Value, name: child["name"].stringValue, pin: child["pin"].stringValue))
                    }
                    Allow2.shared._children = newChildren
                    self.delegate?.Allow2PairingCompleted(result: Allow2Response.PairResult(Allow2PairResult( children: Allow2.shared.children )))
                }
            }
            task.resume()
            
        } catch (let err) {
            print(err)
        }
    }
}

extension Allow2PairingViewController : SKStoreProductViewControllerDelegate {
    
}

class Debouncer: NSObject {
    var callback: (() -> ())
    var delay: Double
    weak var timer: Timer?
    
    init(delay: Double, callback: @escaping (() -> ())) {
        self.delay = delay
        self.callback = callback
    }
    
    func call() {
        timer?.invalidate()
        let nextTimer = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(Debouncer.fireNow), userInfo: nil, repeats: false)
        timer = nextTimer
    }
    
    @objc func fireNow() {
        self.callback()
    }
}
