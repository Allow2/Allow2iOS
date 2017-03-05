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
        
        let json = "{\"uuid\":\"\(UIDevice.currentDevice().identifierForVendor!.UUIDString)\", \"name\":\"\(name.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet()) ?? "")\", \"deviceToken\": \"\(deviceToken ?? "MISSING")\"}"

        let data = json.dataUsingEncoding(NSISOLatin1StringEncoding, allowLossyConversion: false)
        
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        
        let qrcodeCIImage = filter.outputImage!
        
        let cgImage = CIContext(options:nil).createCGImage(qrcodeCIImage, fromRect: qrcodeCIImage.extent)!
        UIGraphicsBeginImageContext(CGSizeMake(size.width * UIScreen.mainScreen().scale, size.height * UIScreen.mainScreen().scale))
        let context = UIGraphicsGetCurrentContext()!
        CGContextSetInterpolationQuality(context, .None)
        CGContextDrawImage(context, CGContextGetClipBoundingBox(context), cgImage)
        let preImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        
        let qrCodeImage = UIImage(CGImage: preImage.CGImage!, scale: 1.0/UIScreen.mainScreen().scale, orientation: .DownMirrored)
        return qrCodeImage
    }
}
