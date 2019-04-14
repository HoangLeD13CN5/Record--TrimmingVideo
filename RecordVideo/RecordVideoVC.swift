import UIKit
import AVFoundation
import Photos

class RecordVideoVC: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    // MARK: - UI Properties
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var recordVideoBtn: UIButton!
    @IBOutlet weak var veticalSlider: VerticalSlider!
    @IBOutlet weak var lblTime: UILabel!
    @IBOutlet weak var btnSwitchVideo: UIButton!
    
    // MARK: - Properties
    var captureSession = AVCaptureSession()
    var previewLayer = AVCaptureVideoPreviewLayer()
    var movieOutput = AVCaptureMovieFileOutput()
    var videoCaptureDevice : AVCaptureDevice?
    var activeInput: AVCaptureDeviceInput!
    private let sessionQueue = DispatchQueue(label: "session queue") // Communicate with the session
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera, .builtInDualCamera],
        mediaType: .video,
        position: .unspecified)
    var currentURL:URL?
    var time:Int = 0
    var timer: Timer?
    
    // MARK: - ViewController Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        if setupSession() {
            setupPreview()
            startSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.title = "Record_Video"
        let textAttributes = [NSAttributedString.Key.foregroundColor:UIColor.white]
        self.navigationController?.navigationBar.titleTextAttributes = textAttributes
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    // MARK: - Initialization
    func setupSession() -> Bool{
        captureSession.sessionPreset = AVCaptureSession.Preset.high
        
        // Setup Camera
        self.videoCaptureDevice = AVCaptureDevice.default(for: AVMediaType.video)!
        
        do {
            
            let input = try AVCaptureDeviceInput(device: videoCaptureDevice!)
            
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                activeInput = input
                self.veticalSlider.slider.maximumValue = Float(self.getMaxZoomCamera())
                self.veticalSlider.slider.minimumValue = 1.0
                self.veticalSlider.slider.value = 1.0
                self.veticalSlider.slider.addTarget(self, action: #selector(self.valueChanged), for: .valueChanged)
            }
        } catch {
            print("Error setting device video input: \(error)")
            return false
        }
        
        // Setup Microphone
        let microphone = AVCaptureDevice.default(for: AVMediaType.audio)!
        
        do {
            let micInput = try AVCaptureDeviceInput(device: microphone)
            if captureSession.canAddInput(micInput) {
                captureSession.addInput(micInput)
            }
        } catch {
            print("Error setting device audio input: \(error)")
            return false
        }
        
        
        // Movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }
        return true
    }
    
    func setupPreview() {
        // Configure previewLayer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.connection!.videoOrientation = transformOrientation(orientation: UIInterfaceOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!)
        let bounds: CGRect = videoView.layer.bounds
        previewLayer.frame = videoView.layer.bounds
        previewLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        videoView.layer.addSublayer(previewLayer)
    }
    
    //MARK: - Action Entity
    func startSession() {
        
        if !captureSession.isRunning {
            videoQueue().async {
                self.captureSession.startRunning()
            }
        }
    }
    
    func stopSession() {
        if captureSession.isRunning {
            videoQueue().async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func videoQueue() -> DispatchQueue {
        return DispatchQueue.main
    }
    
    func startCountTime(){
        if timer == nil {
            self.time = 0
            self.timer = Timer.scheduledTimer(timeInterval: 1,
                                              target: self,
                                              selector: #selector(self.updateTime),
                                              userInfo: nil,
                                              repeats: true)
        }
    }
    
    func stopTimer() {
        if timer != nil {
            timer?.invalidate()
            timer = nil
        }
    }
    
    func getMaxZoomCamera() -> CGFloat {
        let maxZoom:CGFloat = 4.0
        if activeInput.device.activeFormat.videoMaxZoomFactor < maxZoom {
            return self.activeInput.device.activeFormat.videoMaxZoomFactor
        }
        return maxZoom
    }
    
    @objc func updateTime() {
        self.time = self.time + 1
        var timeString = "00:00:\(self.time)"
        if self.time <= 9 {
            timeString = "00:00:0\(self.time)"
        }
        
        let timeHour = Int(self.time/3600)
        var timeHourString = "\(timeHour)"
        if timeHour <= 9 {
            timeHourString = "0\(timeHour)"
        }
        let timeMiu = Int((self.time - timeHour*3600)/60)
        var timeMiuString = "\(timeMiu)"
        if timeMiu <= 9 {
            timeMiuString = "0\(timeMiu)"
        }
        let timeSec = self.time - timeHour*3600 - timeMiu*60
        var timeSecString = "\(timeSec)"
        if timeSec <= 9 {
            timeSecString = "0\(timeSec)"
        }
        timeString = "\(timeHourString):\(timeMiuString):\(timeSecString)"
        self.lblTime.text = timeString
    }
   
    // MARK:  - UI Action
    @IBAction func startOrStopVideo(_ sender: Any) {
        if movieOutput.isRecording {
            recordVideoBtn.setImage(UIImage(named: "ic_play_record"), for: .normal)
            self.lblTime.text = "00:00"
            self.stopTimer()
            self.btnSwitchVideo.isHidden = false
            movieOutput.stopRecording()
        } else {
            self.btnSwitchVideo.isHidden = true
            recordVideoBtn.setImage(UIImage(named: "ic_record_playing"), for: .normal)
            let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let fileUrl = paths[0].appendingPathComponent("output.mov")
            try? FileManager.default.removeItem(at: fileUrl)
            let connection = movieOutput.connection(with: AVMediaType.video)
            
            if (connection?.isVideoOrientationSupported)! {
                connection?.videoOrientation = self.currentVideoOrientation()
            }
            
            if (connection?.isVideoStabilizationSupported)! {
                connection?.preferredVideoStabilizationMode = AVCaptureVideoStabilizationMode.auto
            }
            let device = activeInput.device
            if (device.isSmoothAutoFocusSupported) {
                
                do {
                    try device.lockForConfiguration()
                    device.isSmoothAutoFocusEnabled = false
                    device.unlockForConfiguration()
                } catch {
                    print("Error setting configuration: \(error)")
                }
                
            }
            //EDIT2: And I forgot this
            movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
            self.startCountTime()
        }
    }
    
    @IBAction func pinchZoomCamera(_ sender: UIPinchGestureRecognizer) {
        
        let device = activeInput.device
        
        if sender.state == .changed {
            let maxZoomFactor:CGFloat = self.getMaxZoomCamera()
            let pinchVelocityDividerFactor: CGFloat = 5.0
            
            do {
                
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                
                let desiredZoomFactor = device.videoZoomFactor + atan2(sender.velocity, pinchVelocityDividerFactor)
                self.veticalSlider.slider.value = Float(max(1.0, min(desiredZoomFactor, maxZoomFactor)))
                device.videoZoomFactor = max(1.0, min(desiredZoomFactor, maxZoomFactor))
                
            } catch {
                print(error)
            }
        }
    }
    
    @objc func valueChanged(sender: UISlider) {
        // round the slider position to the nearest index of the numbers array
        let value = self.veticalSlider.slider.value
        let device = activeInput.device
        do {
            
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.videoZoomFactor = CGFloat(value)
        } catch {
            print(error)
        }
    }
    
    @IBAction func tapCancelRecordVIdeo(_ sender: Any) {
        
    }
    
    @IBAction func switchCamera(_ sender: Any) {
        self.recordVideoBtn.isEnabled = false
        self.btnSwitchVideo.isEnabled = false
        sessionQueue.async {
            let currentVideoDevice = self.activeInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInDualCamera
                
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInWideAngleCamera
            }
            
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, look for a device with both the preferred position and device type. Otherwise, look for a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.captureSession.beginConfiguration()
                    
                    // Remove the existing device input first, since using the front and back camera simultaneously is not supported.
                    self.captureSession.removeInput(self.activeInput)
                    
                    if self.captureSession.canAddInput(videoDeviceInput) {
                        self.captureSession.addInput(videoDeviceInput)
                        self.activeInput = videoDeviceInput
                    } else {
                        self.captureSession.addInput(self.activeInput)
                    }
                    
                    if let connection = self.movieOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.captureSession.commitConfiguration()
                } catch {
                    print("Error occured while creating video device input: \(error)")
                }
            }
            
            DispatchQueue.main.async {
                self.recordVideoBtn.isEnabled = true
                self.btnSwitchVideo.isEnabled = true
            }
        }
    }
    
    // MARK:  - Utils Methods
    func getDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceDescoverySession = AVCaptureDevice.DiscoverySession.init(deviceTypes:         [AVCaptureDevice.DeviceType.builtInWideAngleCamera],
                                                                           mediaType: AVMediaType.video,
                                                                           position: AVCaptureDevice.Position.unspecified)
        for device in deviceDescoverySession.devices {
            if device.hasMediaType(AVMediaType.video) {
                if device .position == position{
                    return device
                }
            }
        }
        return nil
    }
    
    func currentVideoOrientation() -> AVCaptureVideoOrientation {
        var orientation: AVCaptureVideoOrientation
        
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = AVCaptureVideoOrientation.portrait
        case .landscapeRight:
            orientation = AVCaptureVideoOrientation.landscapeLeft
        case .portraitUpsideDown:
            orientation = AVCaptureVideoOrientation.portraitUpsideDown
        default:
            orientation = AVCaptureVideoOrientation.landscapeRight
        }
        
        return orientation
    }
    
    func transformOrientation(orientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}

// MARK:  - AVCaptureFileOutputRecordingDelegate
extension RecordVideoVC : AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        // save video to camera roll
        if error == nil {
            self.saveVideo(url: outputFileURL)
        }
    }
}

//MARK: - Export video
extension RecordVideoVC {
    func saveVideo(url:URL) {
        do {
            let urlSave = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("abc.mp4")
            try FileManager.default.removeItem(at: urlSave)
            var listTimeRange:[(TimeInterval,TimeInterval)] = []
            // save file video cut
            let asset = AVURLAsset(url: url)
            let duration = asset.duration
            let durationTimeAsset = CMTimeGetSeconds(duration)
            listTimeRange.append((0.0, durationTimeAsset - 5.0))
            
            
            // trimming video
            let composition = AVMutableComposition()
            let track = asset.tracks(withMediaType: .video)[0]
            let audio = asset.tracks(withMediaType: .audio)[0]
            let mainInstruction = AVMutableVideoCompositionInstruction()
            var durationTime = 0.0
            for (startTime,endTime) in listTimeRange {
                let compositionTrack = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
                
                let audioTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: 0)
                
                let timeStart = CMTime(seconds: startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                let rangeTimeEnd = CMTime(seconds: endTime - startTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                
                let timeRange = CMTimeRange(start: timeStart, duration: rangeTimeEnd)
                
                try compositionTrack?.insertTimeRange(timeRange, of: track, at: durationTime == 0 ? CMTime.zero : CMTime(seconds: durationTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
                
                try audioTrack?.insertTimeRange(timeRange,
                                                of: audio,
                                                at: durationTime == 0 ? CMTime.zero : CMTime(seconds: durationTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
                
                durationTime = durationTime + (endTime - startTime)
                let instruction = VideoHelper.videoCompositionInstruction(compositionTrack!, asset: asset)
                mainInstruction.layerInstructions.append(instruction)
            }
            
            composition.removeTimeRange(CMTimeRange(start: CMTime(seconds: durationTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), end: composition.duration))
            
            mainInstruction.timeRange = CMTimeRangeMake(start: CMTime.zero,duration: CMTime(seconds: durationTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC)))
            let mainComposition = AVMutableVideoComposition()
            mainComposition.instructions = [mainInstruction]
            mainComposition.frameDuration = CMTimeMake(value: 1, timescale: 30)
            mainComposition.renderSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
            
            // create exporter and export
            let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
            exporter!.outputURL = urlSave
            exporter!.outputFileType = AVFileType.mov
            exporter!.shouldOptimizeForNetworkUse = true
            exporter!.videoComposition = mainComposition
            exporter!.exportAsynchronously() {
                DispatchQueue.main.async {
                    self.exportDidFinish(exporter!)
                }
            }
        }catch _ as NSError {}
    }
    
    func exportDidFinish(_ session: AVAssetExportSession) {
        guard
            session.status == AVAssetExportSession.Status.completed, let saveUrl = session.outputURL
            else {
                print("Error \(String(describing: session.error))")
                return
        }
        
        // save video in Photo
        let saveVideoToPhotos = {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: saveUrl)
            }) { saved, error in
                let success = saved && (error == nil)
                let title = success ? "Success" : "Error"
                let message = success ? "Video saved" : "Failed to save video"
                
                let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
        
        // Ensure permission to access Photo Library
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    saveVideoToPhotos()
                }
            }
        } else {
            saveVideoToPhotos()
        }
    }
}
