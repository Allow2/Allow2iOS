//
//  DayTypePickerCell.swift
//  Allow2
//
//  Created by Andrew on 14/2/18.
//  Copyright © 2018 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

protocol DayTypePickerCellDelegate {
    func dayTypePickerCell(_ cell: DayTypePickerCell, didChooseDayType dayType: Allow2Day)
}

class DayTypePickerCell: UITableViewCell {
    
    @IBOutlet var picker: UIPickerView?
    
    var delegate: DayTypePickerCellDelegate?
    private var _dayTypes : [ Allow2Day ]?
    var dayTypes : [ Allow2Day ]? {
        didSet {
            _dayTypes = dayTypes?.sorted(by: { (a, b) -> Bool in
                return a.name.localizedCompare(b.name) == .orderedAscending
            })
            DispatchQueue.main.async {
                self.picker?.reloadComponent(0)
            }
        }
    }
}

extension DayTypePickerCell: UIPickerViewDataSource {
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return (_dayTypes?.count ?? 0) + 1
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if (row == 0) {
            return "Do Not Change"
        }
        //        if (row == 1) {
        //            return "Set Back to Default"
        //        }
        let dayType = _dayTypes?[row - 1]
        return dayType?.name ?? ""
    }
}

extension DayTypePickerCell: UIPickerViewDelegate {
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if (row == 0) {
            delegate?.dayTypePickerCell(self, didChooseDayType: Allow2Day(id:0, name:"Do Not Change"))
            return
        }
        //        if (row == 1) {
        //            return "Set Back to Default"
        //        }
        let dayType = _dayTypes![row - 1]
        delegate?.dayTypePickerCell(self, didChooseDayType: dayType)
    }
}

