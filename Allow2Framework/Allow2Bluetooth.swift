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

class Allow2Bluetooth : NSObject, CBPeripheralManagerDelegate {

    let uuid = NSUUID(UUIDString: "e170385e-f3fd-4834-a5e4-766ef993e83e")!
    
    var beaconRegion : CLBeaconRegion?
    var peripheralManager: CBPeripheralManager!
    
    var isBroadcasting = false
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }
    
    func startAdvertising() {
        if !isBroadcasting {
            if self.peripheralManager.state == .PoweredOn {

                self.beaconRegion = CLBeaconRegion(proximityUUID:uuid, major:1, minor:1, identifier:"com.allow2.device")
                let dict = self.beaconRegion!.peripheralDataWithMeasuredPower(nil) as NSDictionary
                self.peripheralManager.startAdvertising(dict as? [String : AnyObject])
                isBroadcasting = true
            }
        }
    }
    
    func stopAdvertising() {
        if isBroadcasting {
            self.peripheralManager.stopAdvertising()
            isBroadcasting = false
        }
    }
    
    func peripheralManagerDidUpdateState(peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .PoweredOn:
            print("Bluetooth Status: Turned On")
            
        case .PoweredOff:
            stopAdvertising()
            print("Bluetooth Status: Turned Off")
            
        case .Resetting:
            print("Bluetooth Status: Resetting")
            
        case .Unauthorized:
            print("Bluetooth Status: Not Authorized")
            
        case .Unsupported:
            print("Bluetooth Status: Not Supported")
            
        default:
            print("Bluetooth Status: Unknown")
        }
    }
}
