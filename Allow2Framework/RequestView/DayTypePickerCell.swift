//
//  DayTypePickerCell.swift
//  Allow2
//
//  Created by Andrew on 14/2/18.
//  Copyright © 2018 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

protocol DayTypePickerCellDelegate {
    func dayTypePickerCellCell(_ cell: DayTypePickerCell, didChooseDayType dayType: UInt64)
}

class DayTypePickerCell: UITableViewCell, UIPickerViewDataSource, UIPickerViewDelegate {
    
    @IBOutlet var picker: UIPickerView?
    
    var delegate: DayTypePickerCellDelegate?

    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return 4
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return "option"
    }
}
