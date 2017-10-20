//
//  MessageCell.swift
//  Allow2
//
//  Created by Andrew Longhorn on 20/10/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

protocol MessageCellDelegate {
    func messageCell(_ cell: MessageCell, didChangeContent text: String)
}

class MessageCell: UITableViewCell {
    
    @IBOutlet var messageField: UITextField?
    var delegate: MessageCellDelegate?
    
   // @IBAction func textFieldDidChane
}
