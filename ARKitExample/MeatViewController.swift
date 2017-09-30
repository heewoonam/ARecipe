/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 Main view controller for the AR experience.
 */

import ARKit
import SceneKit
import UIKit
import Vision
import AVFoundation
import AVKit

class MeatViewController: UIViewController {
    
    typealias Prediction = (String, Double)
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var camerapreview: UIImageView!
    
    @IBOutlet weak var topLine: UIView!
    @IBOutlet weak var leftLine: UIView!
    @IBOutlet weak var rightLine: UIView!
    @IBOutlet weak var bottomLine: UIView!
    @IBOutlet weak var surfaceLabel: UILabel!
    @IBOutlet weak var checkButton: UIButton!
    @IBOutlet weak var timerView: UIView!
    var request: VNCoreMLRequest!
    let model = MobileNet()
    var player : AVPlayer!
    // MARK: - ARKit Config Properties
    
    var screenCenter: CGPoint?
    var predCount = 0
    let session = ARSession()
    let standardConfiguration: ARWorldTrackingConfiguration = {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        return configuration
    }()
    
    // MARK: - Virtual Object Manipulation Properties
    
    var dragOnInfinitePlanesEnabled = false
    var virtualObjectManager: VirtualObjectManager!
    
    var isLoadingObject: Bool = false {
        didSet {
            if (self.addObjectButton != nil) {
                DispatchQueue.main.async {
                    //                self.settingsButton.isEnabled = !self.isLoadingObjec
                    self.addObjectButton.isEnabled = !self.isLoadingObject
                    self.restartExperienceButton.isEnabled = !self.isLoadingObject
                }
            }
        }
    }
    
    // MARK: - Other Properties
    
    var textManager: MeatTextManager!
    var restartExperienceButtonIsEnabled = true
    
    // MARK: - UI Elements
    
    var spinner: UIActivityIndicatorView?
    
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var messagePanel: UIView!
    @IBOutlet weak var messageLabel: UILabel!
    @IBOutlet weak var addObjectButton: UIButton!
    @IBOutlet weak var restartExperienceButton: UIButton!
    
    // MARK: - Queues
    
    let serialQueue = DispatchQueue(label: "com.apple.arkitexample.serialSceneKitQueue")
    
    let semaphore = DispatchSemaphore(value: 2)
    var coreMLstart = false
    var placedObject = false
    
    func setUpVision() {
        guard let visionModel = try? VNCoreMLModel(for: model.model) else {
            print("Error: could not create Vision model")
            return
        }
        
        request = VNCoreMLRequest(model: visionModel, completionHandler: requestDidComplete)
        request.imageCropAndScaleOption = .centerCrop
    }

    
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        Setting.registerDefaults()
        setupUIControls()
        setupScene()
        setUpVision()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        if ARWorldTrackingConfiguration.isSupported {
            // Start the ARSession.
            resetTracking()
        } else {
            // This device does not support 6DOF world tracking.
            let sessionErrorMsg = "This app requires world tracking. World tracking is only available on iOS devices with A9 processor or newer. " +
            "Please quit the application."
            displayErrorMessage(title: "Unsupported platform", message: sessionErrorMsg, allowRestart: false)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }
    
    // MARK: - Setup
    
    func setupScene() {
        // Synchronize updates via the `serialQueue`.
        virtualObjectManager = VirtualObjectManager(updateQueue: serialQueue)
        virtualObjectManager.delegate = self
        
        // set up scene view
        sceneView.setup()
        sceneView.delegate = self
        sceneView.session = session
        
        // sceneView.showsStatistics = true
        
        sceneView.scene.enableEnvironmentMapWithIntensity(25, queue: serialQueue)
        
        setupFocusSquare()
        
        DispatchQueue.main.async {
            self.screenCenter = self.sceneView.bounds.mid
        }
    }
    
    func setupUIControls() {
        textManager = MeatTextManager(viewController: self)
        
        // Set appearance of message output panel
        messagePanel.layer.cornerRadius = 3.0
        messagePanel.clipsToBounds = true
        messagePanel.isHidden = true
        messageLabel.text = ""
    }
    
    // MARK: - Gesture Recognizers
    
//    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//        virtualObjectManager.reactToTouchesBegan(touches, with: event, in: self.sceneView)
//    }
//
//    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
//        virtualObjectManager.reactToTouchesMoved(touches, with: event)
//    }
//
//    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
//        if virtualObjectManager.virtualObjects.isEmpty {
//            chooseObject(addObjectButton)
//            return
//        }
//        virtualObjectManager.reactToTouchesEnded(touches, with: event)
//    }
//
//    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
//        virtualObjectManager.reactToTouchesCancelled(touches, with: event)
//    }
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
    
    func requestDidComplete(request: VNRequest, error: Error?) {
        if let observations = request.results as? [VNClassificationObservation] {
            
            // The observations appear to be sorted by confidence already, so we
            // take the top 5 and map them to an array of (String, Double) tuples.
            let top5 = observations.prefix(through: 4)
                .map { ($0.identifier, Double($0.confidence)) }
            
            DispatchQueue.main.async {
                self.show(results: top5)
                self.semaphore.signal()
            }
        }
    }
    
    func show(results: [Prediction]) {
        var s: [String] = []
        var exists = false
        for (i, pred) in results.enumerated() {
            s.append(String(format: "%d: %@ (%3.2f%%)", i + 1, pred.0, pred.1 * 100))
            if (pred.0 == "frying pan, frypan, skillet") {
                exists = true
            }
        }
        if (exists) {
            predCount += 1
        }
        else {
            predCount = 0
        }
        if (predCount > 2) {
            leftLine.isHidden = true
            rightLine.isHidden = true
            topLine.isHidden = true
            bottomLine.isHidden = true
            if (placedObject == false) {
                chooseObject(UIButton())
                placedObject = true
                self.coreMLstart = false
                checkButton.isHidden = false
            }
        }
        else {
            leftLine.isHidden = false
            rightLine.isHidden = false
            topLine.isHidden = false
            bottomLine.isHidden = false
        }
        print (s.joined(separator: "\n"))
//        predictionLabel.text = s.joined(separator: "\n")
        
    }
    
    func resize(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let imageSide = 227
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        let ciContext = CIContext()
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        let rect: CGRect = CGRect(x: 422, y: 136, width: 436, height: 448)
        // Create bitmap image from context using the rect
        let imageRef: CGImage = cgImage!.cropping(to: rect)!
        ciImage = CIImage(cgImage: imageRef)
        
//        DispatchQueue.main.async {
//            self.camerapreview.image = UIImage(ciImage: ciImage)
//        }
        
        var resizeBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(imageSide), Int(imageSide), CVPixelBufferGetPixelFormatType(pixelBuffer), nil, &resizeBuffer)
        ciContext.render(ciImage, to: resizeBuffer!)
        return resizeBuffer
    }
    
    // MARK: - Planes
    
    var planes = [ARPlaneAnchor: Plane]()
    
    func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
        
        let plane = Plane(anchor)
        planes[anchor] = plane
        node.addChildNode(plane)
        
        textManager.cancelScheduledMessage(forType: .planeEstimation)
        textManager.showMessage("SURFACE DETECTED")

        if virtualObjectManager.virtualObjects.isEmpty {
            textManager.scheduleMessage("TAP + TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .contentPlacement)
        }
    }
    
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
            plane.update(anchor)
        }
    }
    
    func removePlane(anchor: ARPlaneAnchor) {
        if let plane = planes.removeValue(forKey: anchor) {
            plane.removeFromParentNode()
        }
    }
    
    func resetTracking() {
        session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
        leftLine.isHidden = false
        rightLine.isHidden = false
        topLine.isHidden = false
        bottomLine.isHidden = false
        checkButton.isHidden = true
        surfaceLabel.isHidden = true
        textManager.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT",
                                    inSeconds: 7.5,
                                    messageType: .planeEstimation)
        if (self.coreMLstart == false){
            self.surfaceLabel.isHidden = false
            self.surfaceLabel.text = "스테이크를 프라이팬에 올려주세요"
            DispatchQueue.global().async {
                sleep(8)
                self.coreMLstart = true
                while (self.coreMLstart) {
                    self.semaphore.wait()
                    self.predict(pixelBuffer: self.resize(pixelBuffer: (self.session.currentFrame?.capturedImage)!)!)
                    usleep(200 * 1000)
                }
                Thread.current.cancel()
            }
        }
    }
    
    // MARK: - Focus Square
    
    var focusSquare: FocusSquare?
    
    func setupFocusSquare() {
        serialQueue.async {
            self.focusSquare?.isHidden = true
            self.focusSquare?.removeFromParentNode()
            self.focusSquare = FocusSquare()
            self.sceneView.scene.rootNode.addChildNode(self.focusSquare!)
        }
        
        textManager.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
    }
    
    func updateFocusSquare() {
        guard let screenCenter = screenCenter else { return }
        
        DispatchQueue.main.async {
            var objectVisible = false
            for object in self.virtualObjectManager.virtualObjects {
                if self.sceneView.isNode(object, insideFrustumOf: self.sceneView.pointOfView!) {
                    objectVisible = true
                    break
                }
            }
            
            if objectVisible {
                self.focusSquare?.hide()
            } else {
                self.focusSquare?.unhide()
            }
            
            let (worldPos, planeAnchor, _) = self.virtualObjectManager.worldPositionFromScreenPosition(screenCenter,
                                                                                                       in: self.sceneView,
                                                                                                       objectPos: self.focusSquare?.simdPosition)
            if let worldPos = worldPos {
                self.serialQueue.async {
                    self.focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
                }
                self.textManager.cancelScheduledMessage(forType: .focusSquare)
            }
        }
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
        // Blur the background.
        textManager.blurBackground()
        
        if allowRestart {
            // Present an alert informing about the error that has occurred.
            let restartAction = UIAlertAction(title: "Reset", style: .default) { _ in
                self.textManager.unblurBackground()
                self.restartExperience(self)
            }
            textManager.showAlert(title: title, message: message, actions: [restartAction])
        } else {
            textManager.showAlert(title: title, message: message, actions: [])
        }
    }
    
}

extension MeatViewController: ARSCNViewDelegate {
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        updateFocusSquare()
        
        // If light estimation is enabled, update the intensity of the model's lights and the environment map
        if let lightEstimate = session.currentFrame?.lightEstimate {
            sceneView.scene.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 40, queue: serialQueue)
        } else {
            sceneView.scene.enableEnvironmentMapWithIntensity(40, queue: serialQueue)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        serialQueue.async {
            self.addPlane(node: node, anchor: planeAnchor)
            self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        serialQueue.async {
            self.updatePlane(anchor: planeAnchor)
            self.virtualObjectManager.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor, planeAnchorNode: node)
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
        serialQueue.async {
            self.removePlane(anchor: planeAnchor)
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        textManager.showTrackingQualityInfo(for: camera.trackingState, autoHide: true)
        
        switch camera.trackingState {
        case .notAvailable:
            fallthrough
        case .limited:
            textManager.escalateFeedback(for: camera.trackingState, inSeconds: 3.0)
        case .normal:
            textManager.cancelScheduledMessage(forType: .trackingStateEscalation)
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard let arError = error as? ARError else { return }
        
        let nsError = error as NSError
        var sessionErrorMsg = "\(nsError.localizedDescription) \(nsError.localizedFailureReason ?? "")"
        if let recoveryOptions = nsError.localizedRecoveryOptions {
            for option in recoveryOptions {
                sessionErrorMsg.append("\(option).")
            }
        }
        
        let isRecoverable = (arError.code == .worldTrackingFailed)
        if isRecoverable {
            sessionErrorMsg += "\nYou can try resetting the session or quit the application."
        } else {
            sessionErrorMsg += "\nThis is an unrecoverable error that requires to quit the application."
        }
        
        displayErrorMessage(title: "We're sorry!", message: sessionErrorMsg, allowRestart: isRecoverable)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        textManager.blurBackground()
        textManager.showAlert(title: "Session Interrupted", message: "The session will be reset after the interruption has ended.")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        textManager.unblurBackground()
        session.run(standardConfiguration, options: [.resetTracking, .removeExistingAnchors])
        restartExperience(self)
        textManager.showMessage("RESETTING SESSION")
    }
}

extension MeatViewController: UIPopoverPresentationControllerDelegate {
    
    enum SegueIdentifier: String {
        case showSettings
        case showObjects
    }
    
    // MARK: - Interface Actions
    
    @IBAction func chooseObject(_ button: UIButton) {
        // Abort if we are about to load another object to avoid concurrent modifications of the scene.
        if isLoadingObject { return }
        
        textManager.cancelScheduledMessage(forType: .contentPlacement)
        
        let definition = VirtualObjectManager.availableObjects[1]
        let object = VirtualObject(definition: definition)
        let position = focusSquare?.lastPosition ?? float3(0)
        virtualObjectManager.loadVirtualObject(object, to: position, cameraTransform: session.currentFrame!.camera.transform)
        if object.parent == nil {
            serialQueue.async {
                self.sceneView.scene.rootNode.addChildNode(object)
            }
        }
        
        
        
        //        performSegue(withIdentifier: SegueIdentifier.showObjects.rawValue, sender: button)
    }
    
    /// - Tag: restartExperience
    @IBAction func restartExperience(_ sender: Any) {
        guard restartExperienceButtonIsEnabled, !isLoadingObject else { return }
        
        DispatchQueue.main.async {
            self.coreMLstart = false
            self.predictionLabel.text = ""
            self.placedObject = false
            self.restartExperienceButtonIsEnabled = false
            self.timerView.isHidden = true
            
            self.textManager.cancelAllScheduledMessages()
            self.textManager.dismissPresentedAlert()
            self.textManager.showMessage("STARTING A NEW SESSION")
            
            self.virtualObjectManager.removeAllVirtualObjects()
            if (self.addObjectButton != nil) {
                self.addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
                self.addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
            }
            self.focusSquare?.isHidden = true
            
            self.resetTracking()
            
            self.restartExperienceButton.setImage(#imageLiteral(resourceName: "restart"), for: [])
            
            // Show the focus square after a short delay to ensure all plane anchors have been deleted.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
                self.setupFocusSquare()
            })
            
            // Disable Restart button for a while in order to give the session enough time to restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: {
                self.restartExperienceButtonIsEnabled = true
            })
        }
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    
}

extension MeatViewController: VirtualObjectManagerDelegate {
    
    // MARK: - VirtualObjectManager delegate callbacks
    
    func virtualObjectManager(_ manager: VirtualObjectManager, willLoad object: VirtualObject) {
        if (self.addObjectButton != nil) {
            DispatchQueue.main.async {
                // Show progress indicator
                self.spinner = UIActivityIndicatorView()
                self.spinner!.center = self.addObjectButton.center
                self.spinner!.bounds.size = CGSize(width: self.addObjectButton.bounds.width - 5, height: self.addObjectButton.bounds.height - 5)
                self.addObjectButton.setImage(#imageLiteral(resourceName: "buttonring"), for: [])
                self.sceneView.addSubview(self.spinner!)
                self.spinner!.startAnimating()
                
                self.isLoadingObject = true
            }
        }
    }
    
    func virtualObjectManager(_ manager: VirtualObjectManager, didLoad object: VirtualObject) {
        if (self.addObjectButton != nil) {
            DispatchQueue.main.async {
                self.isLoadingObject = false
                
                // Remove progress indicator
                self.spinner?.removeFromSuperview()
                self.addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
                self.addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])
            }
        }
    }
    
    func virtualObjectManager(_ manager: VirtualObjectManager, couldNotPlace object: VirtualObject) {
        textManager.showMessage("CANNOT PLACE OBJECT\nTry moving left or right.")
    }
    
    @IBAction func startTimer(_ button : UIButton) {
        checkButton.isHidden = true
        surfaceLabel.text = "5분간 구워주세요"
        guard let path = Bundle.main.path(forResource: "timer", ofType:"mov") else {
            debugPrint("timer.mov not found")
            return
        }
        player = AVPlayer(url: URL(fileURLWithPath: path))
        NotificationCenter.default.addObserver(self, selector:#selector(self.playerDidFinishPlaying(note:)),
                                               name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: player.currentItem)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.borderWidth = 0
        playerLayer.frame = self.timerView.bounds
        self.timerView.layer.addSublayer(playerLayer)
        self.timerView.isHidden = false
        player.play()
    }
    
    @objc func playerDidFinishPlaying(note: NSNotification) {
        timerView.isHidden = true
    }
    
    @IBAction func recordTime(_ button : UIButton) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "PaprikaViewController") as! PaprikaViewController;
        if (player != nil && timerView.isHidden == false) {
            vc.playTime = player.currentTime()
        }
        self.present(vc, animated: false, completion: nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        self.coreMLstart = false
    }
    
}


