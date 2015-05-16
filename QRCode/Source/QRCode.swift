//
//  QRCode.swift
//  QRCode
//
//  Created by 刘凡 on 15/5/15.
//  Copyright (c) 2015年 joyios. All rights reserved.
//

import UIKit
import AVFoundation

public class QRCode: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    
    /// corner line width
    var lineWidth: CGFloat
    /// corner stroke color
    var strokeColor: UIColor
    /// the max count for detection
    var maxDetectedCount: Int
    /// current count for detection
    var currentDetectedCount: Int = 0
    /// auto remove sub layers when detection completed
    var autoRemoveSubLayers: Bool
    /// completion call back
    var completedCallBack: ((stringValue: String) -> ())?
    
    ///QRCode init func
    public init(autoRemoveSubLayers: Bool = false, lineWidth: CGFloat = 4, strokeColor: UIColor = UIColor.greenColor(), maxDetectedCount: Int = 20) {
        
        self.lineWidth = lineWidth
        self.strokeColor = strokeColor
        self.maxDetectedCount = maxDetectedCount
        self.autoRemoveSubLayers = autoRemoveSubLayers
    }
    
    deinit {
        if session.running {
            session.stopRunning()
        }
        
        removeAllLayers()
    }
    
    // MARK: - Generate QRCode Image
    public func generateImage(stringValue: String, avatarImage: UIImage?, avatarScale: CGFloat = 0.25, color: CIColor = CIColor(red: 0, green: 0, blue: 0), backColor: CIColor = CIColor(red: 1, green: 1, blue: 1)) -> UIImage? {
        
        let qrFilter = CIFilter(name: "CIQRCodeGenerator")
        qrFilter.setDefaults()
        
        qrFilter.setValue(stringValue.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false), forKey: "inputMessage")
        let ciImage = qrFilter.outputImage
        
        let colorFilter = CIFilter(name: "CIFalseColor")
        colorFilter.setDefaults()
        colorFilter.setValue(ciImage, forKey: "inputImage")
        colorFilter.setValue(color, forKey: "inputColor0")
        colorFilter.setValue(backColor, forKey: "inputColor1")
        
        let transform = CGAffineTransformMakeScale(5, 5)
        let transformedImage = colorFilter.outputImage.imageByApplyingTransform(transform)
        
        let image = UIImage(CIImage: transformedImage)
        
        if avatarImage != nil && image != nil {
            return insertAvatarImage(image!, avatarImage: avatarImage!, scale: avatarScale)
        }
        
        return image
    }

    func insertAvatarImage(codeImage: UIImage, avatarImage: UIImage, scale: CGFloat) -> UIImage {
        
        let rect = CGRectMake(0, 0, codeImage.size.width, codeImage.size.height)
        UIGraphicsBeginImageContext(rect.size)
        
        codeImage.drawInRect(rect)
        
        let avatarSize = CGSizeMake(rect.size.width * scale, rect.size.height * scale)
        let x = (rect.width - avatarSize.width) * 0.5
        let y = (rect.height - avatarSize.height) * 0.5
        avatarImage.drawInRect(CGRectMake(x, y, avatarSize.width, avatarSize.height))

        let result = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return result
    }
    
    // MARK: - Video Scan
    public func scanCode(view: UIView, completion:(stringValue: String)->()) {
        
        completedCallBack = completion
        currentDetectedCount = 0
        
        setupSession()
        setupLayers(view)
    }

    func setupLayers(view: UIView) {
        drawLayer.frame = view.bounds
        view.layer.insertSublayer(drawLayer, atIndex: 0)
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, atIndex: 0)
    }
    
    func setupSession() {
        if session.running {
            println("the capture session is running")
            return
        }
        
        if !session.canAddInput(videoInput) {
            println("can not add input device")
            return
        }
        
        if !session.canAddOutput(dataOutput) {
            println("can not add output device")
            return
        }
        
        session.addInput(videoInput)
        session.addOutput(dataOutput)
        
        dataOutput.metadataObjectTypes = dataOutput.availableMetadataObjectTypes;
        dataOutput.setMetadataObjectsDelegate(self, queue: dispatch_get_main_queue())
        
        session.startRunning()
    }
    
    public func captureOutput(captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [AnyObject]!, fromConnection connection: AVCaptureConnection!) {
     
        clearDrawLayer()
        
        for dataObject in metadataObjects {
            if let codeObject = dataObject as? AVMetadataMachineReadableCodeObject {
                
                if currentDetectedCount++ > maxDetectedCount {
                    session.stopRunning()
                    
                    completedCallBack!(stringValue: codeObject.stringValue)
                    
                    if autoRemoveSubLayers {
                        removeAllLayers()
                    }
                }
                
                // transform codeObject
                drawCodeCorners(previewLayer.transformedMetadataObjectForMetadataObject(codeObject) as! AVMetadataMachineReadableCodeObject)
            }
        }
    }
    
    public func removeAllLayers() {
        previewLayer.removeFromSuperlayer()
        drawLayer.removeFromSuperlayer()
    }
    
    func clearDrawLayer() {
        if drawLayer.sublayers == nil {
            return
        }
        
        for layer in drawLayer.sublayers {
            layer.removeFromSuperlayer()
        }
    }
    
    func drawCodeCorners(codeObject: AVMetadataMachineReadableCodeObject) {
        if codeObject.corners.count == 0 {
            return
        }
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = lineWidth
        shapeLayer.strokeColor = strokeColor.CGColor
        shapeLayer.fillColor = UIColor.clearColor().CGColor
        shapeLayer.path = createPath(codeObject.corners).CGPath
        
        drawLayer.addSublayer(shapeLayer)
    }
    
    func createPath(points: NSArray) -> UIBezierPath {
        let path = UIBezierPath()
        var point = CGPoint()
        
        var index = 0
        CGPointMakeWithDictionaryRepresentation(points[index++] as! CFDictionaryRef, &point)
        path.moveToPoint(point)
        
        while index < points.count {
            CGPointMakeWithDictionaryRepresentation(points[index++] as! CFDictionaryRef, &point)
            path.addLineToPoint(point)
        }
        path.closePath()
        
        return path
    }
    
    /// previewLayer
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        return AVCaptureVideoPreviewLayer(session: self.session)
    }()

    /// drawLayer
    lazy var drawLayer: CALayer = {
        return CALayer()
    }()
    
    /// session
    lazy var session: AVCaptureSession = {
        return AVCaptureSession()
    }()

    /// input
    lazy var videoInput: AVCaptureDeviceInput? = {
        if let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo) {
            return AVCaptureDeviceInput(device: device, error: nil)
        }
        return nil
    }()

    /// output
    lazy var dataOutput: AVCaptureMetadataOutput = {
        return AVCaptureMetadataOutput()
    }()
    
}