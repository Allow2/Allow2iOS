//
//  Allow2+QR.swift
//  Allow2Framework
//
//  Created by Andrew Longhorn on 5/3/17.
//  Copyright © 2017 Allow2 Pty Ltd. All rights reserved.
//

import UIKit

extension Allow2 {
    public func generateQRImage(name: String, withSize size: CGSize) -> UIImage {
        
        let json = "{\"uuid\":\"\(UIDevice.current.identifierForVendor!.uuidString)\", \"name\":\"\(name.addingPercentEncoding(withAllowedCharacters: NSCharacterSet.urlQueryAllowed) ?? "")\", \"deviceToken\": \"\(deviceToken ?? "MISSING")\"}"

        let data = json.data(using: String.Encoding.isoLatin1, allowLossyConversion: false)
        
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
        
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("L", forKey: "inputCorrectionLevel")
            
            if let qrCodeImage = filter.outputImage {
                
                let scaleX : CGFloat = 100.0 //size.width * UIScreen.main.scale
                let scaleY : CGFloat = 100.0 //size.height * UIScreen.main.scale
                
                let transform = CGAffineTransform (scaleX: scaleX, y: scaleY)
                
                let output = qrCodeImage.transformed(by: transform)
                return UIImage(ciImage: output)
            }
        }
        
        return UIImage(named: "Allow2 Logo")!
    }
}
