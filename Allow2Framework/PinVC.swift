//
//  PinVC.swift
//  allow2
//
//  Created by Andrew Longhorn on 19/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//
import UIKit

protocol PinVCDelegate : class {
    func pinVCDidEnterPin(_ pinVC: PinVC, success: Bool)
}

enum PinVCStep {
    case enterPin
    case confirmPin
}

class PinVC : UIViewController {
    
    @IBOutlet var label: UILabel!
    @IBOutlet var pinCode: NPPinCodeField!
    
    public var pin : String?
    
    weak var delegate: PinVCDelegate?
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reset()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pinCode.becomeFirstResponder()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        pinCode.resignFirstResponder()
    }
    
    func reset() {
        pinCode.text = ""
        label.text = "Enter Pin"
        pinCode.becomeFirstResponder()
    }
    
    @IBAction func pinCodeChanged(sender: NPPinCodeField) {
        if sender.isFilled {
            
           if (sender.text != pin) {
                self.view.shake()
                self.reset()
                return
            }
            
            sender.resignFirstResponder()
            //print("Pin code entered.")
            delegate?.pinVCDidEnterPin(self, success: true)
        }
    }
    
    @IBAction func cancel(sender: UIBarButtonItem) {
        pinCode.resignFirstResponder()
        self.dismiss(animated: true)
    }
    
}

extension UIView {
    func shake(){
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = 0.07
        animation.repeatCount = 3
        animation.autoreverses = true
        animation.fromValue = NSValue(cgPoint: CGPoint(x: self.center.x - 10, y: self.center.y))
        animation.toValue = NSValue(cgPoint: CGPoint(x: self.center.x + 10, y: self.center.y))
        self.layer.add(animation, forKey: "position")
    }
}
