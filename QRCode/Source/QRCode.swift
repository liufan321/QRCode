//
//  QRCode.swift
//  QRCode
//
//  Created by 刘凡 on 15/5/15.
//  Copyright (c) 2015年 joyios. All rights reserved.
//

import UIKit
import AVFoundation

open class QRCode: NSObject, AVCaptureMetadataOutputObjectsDelegate {
	
	/// the type of code to generate; the raw value is the name of the filter to use with CoreImage
	public enum CodeType: String {
		// 2D QR code
		case qr = "CIQRCodeGenerator"
		// 1D bar code
		case bar = "CICode128BarcodeGenerator"
	}
    
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
    var completedCallBack: ((_ stringValue: String) -> ())?
    /// the scan rect, default is the bounds of the scan view, can modify it if need
    open var scanFrame: CGRect = CGRect.zero
    
    ///  init function
    ///
    ///  - returns: the scanner object
    public override init() {
        self.lineWidth = 4
        self.strokeColor = UIColor.green
        self.maxDetectedCount = 20
        self.autoRemoveSubLayers = false
        
        super.init()
    }
    
    ///  init function
    ///
    ///  - parameter autoRemoveSubLayers: remove sub layers auto after detected code image
    ///  - parameter lineWidth:           line width, default is 4
    ///  - parameter strokeColor:         stroke color, default is Green
    ///  - parameter maxDetectedCount:    max detecte count, default is 20
    ///
    ///  - returns: the scanner object
    public init(autoRemoveSubLayers: Bool, lineWidth: CGFloat = 4, strokeColor: UIColor = UIColor.green, maxDetectedCount: Int = 20) {
        
        self.lineWidth = lineWidth
        self.strokeColor = strokeColor
        self.maxDetectedCount = maxDetectedCount
        self.autoRemoveSubLayers = autoRemoveSubLayers
    }
    
    deinit {
        if session.isRunning {
            session.stopRunning()
        }
        
        removeAllLayers()
    }
    
    // MARK: - Generate QRCode Image
    ///  generate image
    ///
    ///  - parameter stringValue: string value to encoe
    ///  - parameter avatarImage: avatar image will display in the center of qrcode image
    ///  - parameter avatarScale: the scale for avatar image, default is 0.25
    ///
    ///  - returns: the generated image
    class open func generateImage(_ stringValue: String, avatarImage: UIImage?, avatarScale: CGFloat = 0.25) -> UIImage? {
		return generateImage(stringValue, avatarImage: avatarImage, avatarScale: avatarScale, color: CIColor(color: UIColor.black), backColor: CIColor(color: UIColor.white))
    }
    
    ///  Generate Qrcode Image
    ///
    ///  - parameter stringValue: string value to encoe
    ///  - parameter avatarImage: avatar image will display in the center of qrcode image
    ///  - parameter avatarScale: the scale for avatar image, default is 0.25
    ///  - parameter color:       the CI color for foreground, default is black
	///  - parameter backColor:   the CI color for background, default is white
	///  - parameter codeType:    the type of code, as seen in CodeType (qr, bar)
	///  - parameter width:		  desired width of the output image; if not specified, the size is the filter's default
	///  - parameter height:	  desired height of the output image; if not specified, the size is the filter's default; if only width or height is specified, the transform will be applied keeping the aspect ratio
    ///
    ///  - returns: the generated image
	class open func generateImage(_ stringValue: String, avatarImage: UIImage?, avatarScale: CGFloat = 0.25, color: CIColor, backColor: CIColor, codeType: CodeType = .bar, width: CGFloat? = nil, height: CGFloat? = nil) -> UIImage? {
        
        // generate qrcode image
		let codeFilter = CIFilter(name: codeType.rawValue)!
        codeFilter.setDefaults()
        codeFilter.setValue(stringValue.data(using: String.Encoding.utf8, allowLossyConversion: false), forKey: "inputMessage")
        
        let ciImage = codeFilter.outputImage
		
        let colorFilter = CIFilter(name: "CIFalseColor")!
        colorFilter.setDefaults()
        colorFilter.setValue(ciImage, forKey: kCIInputImageKey)
        colorFilter.setValue(color, forKey: "inputColor0")
        colorFilter.setValue(backColor, forKey: "inputColor1")
		
		// scale qrcode image?
		var transformedImage = colorFilter.outputImage!
		var scaleX: CGFloat?
		var scaleY: CGFloat?
		if let desiredWidth = width {
			let originalWidth = transformedImage.extent.width
			scaleX = desiredWidth / originalWidth
		}
		if let desiredHeight = height {
			let originalHeight = transformedImage.extent.height
			scaleY = desiredHeight / originalHeight
		}
		// if one is nil, it takes the other's value
		if let finalScaleX = scaleX ?? scaleY, let finalScaleY = scaleY ?? scaleX {
			let transform = CGAffineTransform(scaleX: finalScaleX, y: finalScaleY)
			transformedImage = transformedImage.applying(transform)
		}
		
        let image = UIImage(ciImage: transformedImage)
        
        if avatarImage != nil {
            return insertAvatarImage(image, avatarImage: avatarImage!, scale: avatarScale)
        }
        
        return image
    }
    
    class func insertAvatarImage(_ codeImage: UIImage, avatarImage: UIImage, scale: CGFloat) -> UIImage {
        
        let rect = CGRect(x: 0, y: 0, width: codeImage.size.width, height: codeImage.size.height)
        UIGraphicsBeginImageContext(rect.size)
        
        codeImage.draw(in: rect)
        
        let avatarSize = CGSize(width: rect.size.width * scale, height: rect.size.height * scale)
        let x = (rect.width - avatarSize.width) * 0.5
        let y = (rect.height - avatarSize.height) * 0.5
        avatarImage.draw(in: CGRect(x: x, y: y, width: avatarSize.width, height: avatarSize.height))
        
        let result = UIGraphicsGetImageFromCurrentImageContext()
        
        UIGraphicsEndImageContext()
        
        return result!
    }
    
    // MARK: - Video Scan
    ///  prepare scan
    ///
    ///  - parameter view:       the scan view, the preview layer and the drawing layer will be insert into this view
    ///  - parameter completion: the completion call back
    open func prepareScan(_ view: UIView, completion:@escaping (_ stringValue: String)->()) {
        
        scanFrame = view.bounds
        
        completedCallBack = completion
        currentDetectedCount = 0
        
        setupSession()
        setupLayers(view)
    }
    
    /// start scan
    open func startScan() {
        if session.isRunning {
            print("the  capture session is running")
            
            return
        }
        session.startRunning()
    }
    
    /// stop scan
    open func stopScan() {
        if !session.isRunning {
            print("the capture session is not running")
            
            return
        }
        session.stopRunning()
    }
    
    func setupLayers(_ view: UIView) {
        drawLayer.frame = view.bounds
        view.layer.insertSublayer(drawLayer, at: 0)
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }
    
    func setupSession() {
        if session.isRunning {
            print("the capture session is running")
            return
        }
        
        if !session.canAddInput(videoInput) {
            print("can not add input device")
            return
        }
        
        if !session.canAddOutput(dataOutput) {
            print("can not add output device")
            return
        }
        
        session.addInput(videoInput)
        session.addOutput(dataOutput)
        
        dataOutput.metadataObjectTypes = dataOutput.availableMetadataObjectTypes;
        dataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
    }
    
    open func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        
        clearDrawLayer()
        
        for dataObject in metadataObjects {
            
            if let codeObject = dataObject as? AVMetadataMachineReadableCodeObject,
                let obj = previewLayer.transformedMetadataObject(for: codeObject) as? AVMetadataMachineReadableCodeObject {

                if scanFrame.contains(obj.bounds) {
                    currentDetectedCount = currentDetectedCount + 1
                    if currentDetectedCount > maxDetectedCount {
                        session.stopRunning()
                        
                        completedCallBack!(codeObject.stringValue)
                        
                        if autoRemoveSubLayers {
                            removeAllLayers()
                        }
                    }
                    
                    // transform codeObject
                    drawCodeCorners(previewLayer.transformedMetadataObject(for: codeObject) as! AVMetadataMachineReadableCodeObject)
                }
            }
        }
    }
    
    open func removeAllLayers() {
        previewLayer.removeFromSuperlayer()
        drawLayer.removeFromSuperlayer()
    }
    
    func clearDrawLayer() {
        if drawLayer.sublayers == nil {
            return
        }
        
        for layer in drawLayer.sublayers! {
            layer.removeFromSuperlayer()
        }
    }
    
    func drawCodeCorners(_ codeObject: AVMetadataMachineReadableCodeObject) {
        if codeObject.corners.count == 0 {
            return
        }
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.lineWidth = lineWidth
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.path = createPath(codeObject.corners as NSArray).cgPath
        
        drawLayer.addSublayer(shapeLayer)
    }
    
    func createPath(_ points: NSArray) -> UIBezierPath {
        let path = UIBezierPath()

        var point = CGPoint(dictionaryRepresentation: points[0] as! CFDictionary)
        path.move(to: point!)
        
        var index = 1
        while index < points.count {
            point = CGPoint(dictionaryRepresentation: points[index] as! CFDictionary)
            path.addLine(to: point!)
            
            index = index + 1
        }
        path.close()
        
        return path
    }
    
    /// previewLayer
    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: self.session)
        layer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        return layer!
        }()
    
    /// drawLayer
    lazy var drawLayer = CALayer()
    /// session
    lazy var session = AVCaptureSession()
    /// input
    lazy var videoInput: AVCaptureDeviceInput? = {
        
        if let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo) {
            return try? AVCaptureDeviceInput(device: device)
        }
        return nil
        }()
    
    /// output
    lazy var dataOutput = AVCaptureMetadataOutput()
}
