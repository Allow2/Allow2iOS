//
//  Allow2LoginViewController.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 5/3/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

public class Allow2LoginViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    
    @IBOutlet var noChildrenView : UIView?
    @IBOutlet var tableView : UITableView?

    var children = [Allow2Child]()
    
    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.updateChildren()
        NotificationCenter.default.addObserver(self, selector: #selector(Allow2LoginViewController.Allow2CheckResultNotification(notification:)), name: NSNotification.Name.allow2CheckResultNotification, object: nil)
    }
    
    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.allow2CheckResultNotification, object: nil)
    }
    
    func updateChildren() {
        let newChildren = Allow2.shared.children
        children = newChildren.sorted(by: { (a, b) -> Bool in
            a.name > b.name
        })
    }
    
    public func newChildren() {
        self.updateChildren()
        DispatchQueue.main.async {
            self.tableView?.reloadData()
        }
    }
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        let hasChildren = children.count > 0
        self.tableView?.isHidden = !hasChildren
        noChildrenView?.isHidden = hasChildren
        return hasChildren ? 1 : 0
    }
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return children.count
    }
    
    func configureCell(_ cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let child = children[indexPath.row];
        cell.textLabel?.text = child.name
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // create a new cell if needed or reuse an old one
        let cell:UITableViewCell = tableView.dequeueReusableCell(withIdentifier: "ChildCell") as UITableViewCell!
        configureCell(cell, forRowAt: indexPath)
        return cell
    }
    
    
    @objc func Allow2CheckResultNotification(notification:NSNotification) {
        guard let userInfo = notification.userInfo,
            let result  = userInfo["result"] as? Allow2CheckResult else {
                print("No Allow2CheckResult found in notification")
                return
        }
        print("\(result) received")
        
        self.updateChildren()
        DispatchQueue.main.async {
            self.tableView?.reloadData()
        }
    }
}
