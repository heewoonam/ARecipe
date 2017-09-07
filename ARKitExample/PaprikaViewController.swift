import UIKit
import Vision
import CoreMedia

class PaprikaViewController: UIViewController {
    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var predictionLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var camerapreview: UIImageView!
    
    @IBOutlet weak var topLine: UIView!
    @IBOutlet weak var leftLine: UIView!
    @IBOutlet weak var rightLine: UIView!
    @IBOutlet weak var bottomLine: UIView!
    @IBOutlet weak var leftDot: UIImageView!
    @IBOutlet weak var rightDot: UIImageView!
    
    let model = SqueezeNet()
    
    var videoCapture: VideoCapture!
    var request: VNCoreMLRequest!
    var startTimes: [CFTimeInterval] = []
    
    var framesDone = 0
    var frameCapturingStartTime = CACurrentMediaTime()
    let semaphore = DispatchSemaphore(value: 2)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        predictionLabel.text = ""
        timeLabel.text = ""
        
        setUpVision()
        setUpCamera()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        print(#function)
    }
    
    // MARK: - Initialization
    
    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 5
        videoCapture.setUp { success in
            if success {
                // Add the video preview into the UI.
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                self.videoCapture.start()
            }
        }
    }
    
    func setUpVision() {
        guard let visionModel = try? VNCoreMLModel(for: model.model) else {
            print("Error: could not create Vision model")
            return
        }
        
        request = VNCoreMLRequest(model: visionModel, completionHandler: requestDidComplete)
        request.imageCropAndScaleOption = .centerCrop
    }
    
    // MARK: - UI stuff
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        resizePreviewLayer()
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
    
    // MARK: - Doing inference
    
    typealias Prediction = (String, Double)
    
    func predict(pixelBuffer: CVPixelBuffer) {
        // Measure how long it takes to predict a single video frame. Note that
        // predict() can be called on the next frame while the previous one is
        // still being processed. Hence the need to queue up the start times.
        startTimes.append(CACurrentMediaTime())
        
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
            if (pred.0 == "bell pepper") {
                exists = true
            }
        }
        if (exists) {
            leftLine.isHidden = true
            rightLine.isHidden = true
            topLine.isHidden = true
            bottomLine.isHidden = true
            leftDot.isHidden = false
            rightDot.isHidden = false
        }
        else {
            leftLine.isHidden = false
            rightLine.isHidden = false
            topLine.isHidden = false
            bottomLine.isHidden = false
            leftDot.isHidden = true
            rightDot.isHidden = true
        }
        predictionLabel.text = s.joined(separator: "\n")
        
        let elapsed = CACurrentMediaTime() - startTimes.remove(at: 0)
        let fps = self.measureFPS()
        timeLabel.text = String(format: "Elapsed %.5f seconds - %.2f FPS", elapsed, fps)
    }
    
    func measureFPS() -> Double {
        // Measure how many frames were actually delivered per second.
        framesDone += 1
        let frameCapturingElapsed = CACurrentMediaTime() - frameCapturingStartTime
        let currentFPSDelivered = Double(framesDone) / frameCapturingElapsed
        if frameCapturingElapsed > 1 {
            framesDone = 0
            frameCapturingStartTime = CACurrentMediaTime()
        }
        return currentFPSDelivered
    }
    
    func resize(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let imageSide = 227
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        let ciContext = CIContext()
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        let rect: CGRect = CGRect(x: 158, y: 68, width: 163, height: 224)
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
    
}

extension PaprikaViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if let pixelBuffer = pixelBuffer {
            // For better throughput, perform the prediction on a background queue
            // instead of on the VideoCapture queue. We use the semaphore to block
            // the capture queue and drop frames when Core ML can't keep up.
            semaphore.wait()
            DispatchQueue.global().async {
                self.predict(pixelBuffer: self.resize(pixelBuffer: pixelBuffer)!)
            }
        }
    }
}
