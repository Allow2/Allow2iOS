//
//  Allow2Bluetooth.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 11/3/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import Foundation
import CoreLocation
import CoreBluetooth

class Allow2Bluetooth : NSObject {

    let uuid = UUID(uuidString: "E170385E-F3FD-4834-A5E4-766Ef993E83E")!
    let major : CLBeaconMajorValue = UInt16(arc4random_uniform(65536))
    let minor : CLBeaconMinorValue = UInt16(arc4random_uniform(65536))
    
    var beaconRegion : CLBeaconRegion?
    var peripheralManager: CBPeripheralManager!
    
    var shouldAdvertise = false
    var isBroadcasting = false
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }
    
    func startAdvertising() {
        shouldAdvertise = true
        //if !isBroadcasting {
            //if self.peripheralManager.state == .poweredOn {
                self.beaconRegion = CLBeaconRegion(
                    proximityUUID:  uuid,
                    major:          major,
                    minor:          minor,
                    identifier:     "com.allow2.device")
                let dict = NSDictionary(dictionary: self.beaconRegion!.peripheralData(withMeasuredPower: nil)) as! [String: AnyObject]
                print("Bluetooth: Start Advertising")
                self.peripheralManager.startAdvertising(dict)
                isBroadcasting = true
            //}
        //}
    }
    
    func stopAdvertising() {
        shouldAdvertise = false
        pauseAdvertising()
    }
    
    func pauseAdvertising() {
        if isBroadcasting {
            print("Bluetooth: Stop Advertising")
            self.peripheralManager.stopAdvertising()
            isBroadcasting = false
        }
    }
}

// MARK: - CBPeripheralManagerDelegate
extension Allow2Bluetooth: CBPeripheralManagerDelegate {
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("Bluetooth Status: Turned On")
            if shouldAdvertise {
                startAdvertising()
            }
            
        case .poweredOff:
            print("Bluetooth Status: Turned Off")
            pauseAdvertising()
            
        case .resetting:
            print("Bluetooth Status: Resetting")
            
        case .unauthorized:
            print("Bluetooth Status: Not Authorized")
            
        case .unsupported:
            print("Bluetooth Status: Not Supported")
            
        default:
            print("Bluetooth Status: Unknown")
        }
    }
    
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            print("Bluetooth: Failed to start advertising with error:\(error)")
        } else {
            print("Bluetooth: Started advertising")
        }
    }
}
