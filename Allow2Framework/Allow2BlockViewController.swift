//
//  Allow2BlockView.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 7/1/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

public protocol Allow2BlockViewControllerDelegate {
    
}

public class Allow2BlockViewController: UIViewController {
    
    var delegate : Allow2BlockViewControllerDelegate?
    
    private var checkResult : Allow2CheckResult?
    @IBOutlet var dayTypeLabel : UILabel!
    @IBOutlet var descriptionLabel : UILabel!
    
    public func checkResult(checkResult: Allow2CheckResult!) {
        self.checkResult = checkResult
        dayTypeLabel.text = checkResult.today.name
        descriptionLabel.text = checkResult.explanation
    }
    
    @IBAction func newRequest() {
        UIApplication.shared.openURL(URL(string: "https://app.allow2.com:8443/home/tasks")!)
    }
}
