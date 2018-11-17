import UIKit
import AVFoundation
import QuickLook
import Txqrtester

class QRScannerController: UIViewController {
    var captureSession = AVCaptureSession()
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var qrCodeFrameView: UIView?
    
    var connector: TxqrtesterConnector = TxqrtesterNewConnector()
    
    var state: String = ""

    @IBOutlet var messageLabel:UILabel!
    @IBOutlet var topbar: UIView!    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Get the back-facing camera for capturing videos
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera], mediaType: AVMediaType.video, position: .back)
        
        guard let captureDevice = deviceDiscoverySession.devices.first else {
            print("Failed to get the camera device")
            return
        }
        
        do {
            // Get an instance of the AVCaptureDeviceInput class using the previous device object.
            let input = try AVCaptureDeviceInput(device: captureDevice)
            
            // Set the input device on the capture session.
            captureSession.addInput(input)
            
            // Initialize a AVCaptureMetadataOutput object and set it as the output device to the capture session.
            let captureMetadataOutput = AVCaptureMetadataOutput()
            captureSession.addOutput(captureMetadataOutput)
            
            // Set delegate and use the default dispatch queue to execute the call back
            captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            captureMetadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.qr]
            
            // Initialize the video preview layer and add it as a sublayer to the viewPreview view's layer.
            videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
            videoPreviewLayer?.frame = view.layer.bounds
            view.layer.addSublayer(videoPreviewLayer!)
            
            // Start video capture.
            captureSession.startRunning()
            
            // Move the message label and top bar to the front
            view.bringSubview(toFront: messageLabel)
            view.bringSubview(toFront: topbar)
            
            // Initialize QR Code Frame to highlight the QR code
            qrCodeFrameView = UIView()
            
            if let qrCodeFrameView = qrCodeFrameView {
                qrCodeFrameView.layer.borderColor = UIColor.green.cgColor
                qrCodeFrameView.layer.borderWidth = 2
                view.addSubview(qrCodeFrameView)
                view.bringSubview(toFront: qrCodeFrameView)
            }
        } catch {
            // If any error occurs, simply print it out and don't continue any more.
            print(error)
            return
        }
    }
    
    var connState: Bool = false
    var readyForNext: Bool = false
    func processQR(_ str: String) {
        let decoder = connector
        
        // look for websocket connection QR code
        if !connState && str.hasPrefix("ws://") {
            print("got connection info \(str)!")
            do {
                try connector.connect(str)
            } catch {
                print("Failed to connect: \(error).")
                return
            }
            connState = true
            print("connected")
            
            return
        }
        
        if !connState {
            return
        }
        
        // look for "nextRound" qr code
        if !readyForNext && str == "nextRound" {
            // restart decoder
            print("got next round")
            do {
                try connector.startNext()
            } catch {
                print("Failed to send startNext: \(error).")
                return
            }
            decoder.reset()
            readyForNext = true
            return
        }
        
        if !readyForNext {
            return
        }
        
        // now, assume that we're getting encoded TXQR frames
        do {
            try decoder.decodeChunk(str)
        } catch {
            print("Decode chunk error: \(error).")
        }
        
        let complete = decoder.isCompleted()
        let progress = decoder.progress()
        let speed = decoder.speed()
        let readInterval = decoder.readInterval()
        let totalTimeMs = decoder.totalTimeMs()
        print("TotalTimeMS \(totalTimeMs)")
        if totalTimeMs > 10000 { // timeout
            // TODO send result
            do {
                try connector.sendResult(0)
            } catch {
                print("Failed to send result: \(error).")
                return
            }
            messageLabel.text = String(format: "Timeout!")
            readyForNext = false
        }
        
        if complete {
            let totalSize = decoder.totalSize()
            let totalTime = decoder.totalTime()
            
            messageLabel.text = String(format: "Read %@ in %@! Speed: %@", totalSize!, totalTime!, speed!)
            
            // TODO send result
            do {
                try connector.sendResult(totalTimeMs)
            } catch {
                print("Failed to send result: \(error).")
                return
            }
            readyForNext = false
            messageLabel.text = String(format: "Waiting for new QR scan")
        } else {
            messageLabel.text = String(format: "%02d%% [%@] (%dms)", progress, speed!, readInterval)
        }
    }
}

extension QRScannerController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Check if the metadataObjects array is not nil and it contains at least one object.
        if metadataObjects.count == 0 {
            qrCodeFrameView?.frame = CGRect.zero
            return
        }

        // Get the metadata object.
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        
        if metadataObj.type == AVMetadataObject.ObjectType.qr {
            // If the found metadata is equal to the QR code metadata then update the status label's text and set the bounds
            let barCodeObject = videoPreviewLayer?.transformedMetadataObject(for: metadataObj)
            qrCodeFrameView?.frame = barCodeObject!.bounds
            
            if metadataObj.stringValue != nil {
                let str = metadataObj.stringValue!;
                processQR(str)
            }
        }
    }
}
