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
        
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        
        let qrcodeCIImage = filter.outputImage!
        
        let cgImage = CIContext(options:nil).createCGImage(qrcodeCIImage, from: qrcodeCIImage.extent)!
        UIGraphicsBeginImageContext(CGSize(width: size.width * UIScreen.main.scale, height: size.height * UIScreen.main.scale))
        let context = UIGraphicsGetCurrentContext()!
        context.interpolationQuality = .none
        context.draw(cgImage, in:context.boundingBoxOfClipPath)
        let preImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        let qrCodeImage : UIImage = UIImage(cgImage: preImage.cgImage!, scale: 1.0/UIScreen.main.scale, orientation: .downMirrored)
        return qrCodeImage
    }
}
