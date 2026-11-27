import SwiftUI
import AVFoundation
import UIKit

struct Lens: Identifiable, Equatable {
    let id: String
    let title: String
}

final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"viepnlens.camera",qos:.userInitiated)
    private let output=AVCapturePhotoOutput()
    private let meter=AVCaptureVideoDataOutput()
    private var deviceInput:AVCaptureDeviceInput?
    private var devices:[AVCaptureDevice]=[]
    private var callback: ((Result<Data,Error>)->Void)?
    private var captured:Result<Data,Error>?
    private var previous=[Int](), frames=0, motion=0.0
    private var observers=[NSObjectProtocol]()
    private var wanted=false
    @Published var ready=false
    @Published var issue:String?
    @Published var lenses=[Lens]()
    @Published var selected=""
    @Published var front=false
    override init() {
        super.init()
        let nc=NotificationCenter.default
        observers.append(nc.addObserver(forName:AVCaptureSession.wasInterruptedNotification,object:session,queue:.main) { [weak self] _ in
            self?.ready=false;self?.issue="Camera đang tạm dừng."
        })
        observers.append(nc.addObserver(forName:AVCaptureSession.interruptionEndedNotification,object:session,queue:.main) { [weak self] _ in self?.resumeIfWanted() })
        observers.append(nc.addObserver(forName:AVCaptureSession.runtimeErrorNotification,object:session,queue:.main) { [weak self] _ in self?.resumeIfWanted() })
    }
    deinit { for obs in observers { NotificationCenter.default.removeObserver(obs) } }
    private func resumeIfWanted() { queue.async { if self.wanted { self.startSession() } } }
    func start() {
        queue.async { self.wanted=true }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: resumeIfWanted()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] ok in if ok { self?.resumeIfWanted() } else { self?.show("Bật quyền Camera trong Cài đặt để chụp ảnh.") } }
        default: show("Bật quyền Camera trong Cài đặt để chụp ảnh.")
        }
    }
    func stop() { queue.async { self.wanted=false; if self.session.isRunning { self.session.stopRunning() };DispatchQueue.main.async { self.ready=false } } }
    private func show(_ message:String) { DispatchQueue.main.async { self.ready=false;self.issue=message } }
    private func startSession() {
        if deviceInput == nil {
            let discovered=AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.builtInUltraWideCamera,.builtInTelephotoCamera],mediaType:.video,position:.unspecified).devices
            devices=discovered
            guard let main=discovered.first(where:{$0.position == .back && $0.deviceType == .builtInWideAngleCamera}) ?? discovered.first else { show("Thiết bị hiện chưa có camera. Bạn vẫn có thể nhập ảnh vào Timeline.");return }
            session.beginConfiguration()
            session.sessionPreset = .photo
            guard let input=try? AVCaptureDeviceInput(device:main),session.canAddInput(input) else {session.commitConfiguration();show("Không mở được camera.");return}
            session.addInput(input)
            guard session.canAddOutput(output) else {session.removeInput(input);session.commitConfiguration();show("Không thể khởi tạo đầu chụp ảnh.");return}
            deviceInput=input;session.addOutput(output); output.maxPhotoQualityPrioritization = .quality
            meter.videoSettings=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            meter.alwaysDiscardsLateVideoFrames=true
            if session.canAddOutput(meter) { session.addOutput(meter);meter.setSampleBufferDelegate(self,queue:queue) }
            session.commitConfiguration()
        }
        if !session.isRunning { session.startRunning() }
        publish()
    }
    private func label(_ device:AVCaptureDevice)->String {
        switch device.deviceType {
        case .builtInUltraWideCamera: return "0,5×"
        case .builtInTelephotoCamera: return "Tele"
        default: return "1×"
        }
    }
    private func publish() {
        guard let active=deviceInput?.device else {return}
        let list=devices.filter{$0.position==active.position}.sorted{$0.activeFormat.videoFieldOfView > $1.activeFormat.videoFieldOfView}.map{ Lens(id:$0.uniqueID,title:label($0)) }
        let running=session.isRunning && !session.isInterrupted
        DispatchQueue.main.async { self.lenses=list;self.front=active.position == .front;self.selected=active.uniqueID;self.ready=running;self.issue=running ? nil : "Camera đang tạm dừng." }
    }
    func change(to id:String?=nil) {
        queue.async {
            guard self.callback==nil,let old=self.deviceInput else {return}
            let next=id.flatMap { key in self.devices.first(where:{$0.uniqueID==key}) } ?? self.devices.first(where:{$0.position != old.device.position && $0.deviceType == .builtInWideAngleCamera})
            guard let next,next.uniqueID != old.device.uniqueID,let input=try? AVCaptureDeviceInput(device:next) else { return }
            self.session.beginConfiguration();self.session.removeInput(old)
            if self.session.canAddInput(input) { self.session.addInput(input);self.deviceInput=input }
            else if self.session.canAddInput(old) { self.session.addInput(old) }
            self.session.commitConfiguration();self.previous=[];self.motion=0;self.publish()
        }
    }
    func focus(_ point:CGPoint) {
        queue.async {
            guard let d=self.deviceInput?.device,(try? d.lockForConfiguration()) != nil else {return}
            defer {d.unlockForConfiguration()}
            if d.isFocusPointOfInterestSupported && d.isFocusModeSupported(.continuousAutoFocus) { d.focusPointOfInterest=point;d.focusMode = .continuousAutoFocus }
            if d.isExposurePointOfInterestSupported && d.isExposureModeSupported(.continuousAutoExposure) { d.exposurePointOfInterest=point;d.exposureMode = .continuousAutoExposure }
        }
    }
    func capture(flash:Bool,orientation:UIDeviceOrientation, completion:@escaping (Result<Data,Error>)->Void) {
        queue.async {
            guard self.callback==nil,self.session.isRunning,!self.session.isInterrupted,let conn=self.output.connection(with:.video) else {
                DispatchQueue.main.async{completion(.failure(CameraError.missingCamera))};return
            }
            if conn.isVideoOrientationSupported {
                switch orientation {
                case .landscapeLeft: conn.videoOrientation = .landscapeRight
                case .landscapeRight: conn.videoOrientation = .landscapeLeft
                case .portraitUpsideDown: conn.videoOrientation = .portraitUpsideDown
                default: conn.videoOrientation = .portrait
                }
            }
            if conn.isVideoMirroringSupported {conn.automaticallyAdjustsVideoMirroring=false;conn.isVideoMirrored=self.deviceInput?.device.position == .front}
            let settings=AVCapturePhotoSettings()
            settings.photoQualityPrioritization=self.motion > 0.065 ? .balanced : .quality
            if flash, self.deviceInput?.device.hasFlash==true, self.output.supportedFlashModes.contains(.auto) { settings.flashMode = .auto }
            self.callback=completion;self.captured=nil
            self.output.capturePhoto(with:settings,delegate:self)
        }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        let data=photo.fileDataRepresentation()
        queue.async { if let error {self.captured = .failure(error)} else if let data {self.captured = .success(data)} else {self.captured = .failure(CameraError.unreadable)} }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishCaptureFor resolvedSettings:AVCaptureResolvedPhotoSettings,error:Error?) {
        queue.async {
            let result:Result<Data,Error>
            if let error {result = .failure(error)} else {result=self.captured ?? .failure(CameraError.unreadable)}
            let completion=self.callback;self.callback=nil;self.captured=nil
            DispatchQueue.main.async{completion?(result)}
        }
    }
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection) {
        frames += 1
        guard frames % 4 == 0,let buf=CMSampleBufferGetImageBuffer(sampleBuffer),CVPixelBufferGetPlaneCount(buf)>0 else {return}
        CVPixelBufferLockBaseAddress(buf,.readOnly);defer {CVPixelBufferUnlockBaseAddress(buf,.readOnly)}
        guard let ptr=CVPixelBufferGetBaseAddressOfPlane(buf,0)?.assumingMemoryBound(to:UInt8.self) else {return}
        let w=CVPixelBufferGetWidthOfPlane(buf,0), h=CVPixelBufferGetHeightOfPlane(buf,0),stride=CVPixelBufferGetBytesPerRowOfPlane(buf,0)
        var points=[Int]();points.reserveCapacity(48)
        for y in 1...6 {for x in 1...8 {points.append(Int(ptr[(h*y/7)*stride+w*x/9]))}}
        if previous.count==points.count {
            let diff=zip(points,previous).map { $0.0 - $0.1 }
            let mean=diff.reduce(0,+)/diff.count
            let change=Double(diff.reduce(0){$0+abs($1-mean)})/Double(diff.count*255)
            motion=0.5*motion+0.5*change
        }
        previous=points
    }
}
final class Viewfinder: UIView {
    override class var layerClass:AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview:AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onPoint:((CGPoint)->Void)?
    override init(frame:CGRect) {
        super.init(frame:frame);addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tap(_:))))
    }
    required init?(coder:NSCoder) { fatalError() }
    @objc private func tap(_ gesture:UITapGestureRecognizer) {
        let p=gesture.location(in:self)
        onPoint?(preview.captureDevicePointConverted(fromLayerPoint:p))
        let ring=CAShapeLayer();ring.path=UIBezierPath(roundedRect:CGRect(x:p.x-27,y:p.y-27,width:54,height:54),cornerRadius:9).cgPath
        ring.strokeColor=UIColor.systemYellow.cgColor;ring.fillColor=UIColor.clear.cgColor;ring.lineWidth=1.3;layer.addSublayer(ring)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.7){ring.removeFromSuperlayer()}
    }
}
struct CameraPreview:UIViewRepresentable {
    let camera:Camera
    func makeUIView(context:Context)->Viewfinder {
        let v=Viewfinder(frame:.zero);v.preview.session=camera.session;v.preview.videoGravity = .resizeAspect
        v.onPoint={camera.focus($0)};return v
    }
    func updateUIView(_ uiView:Viewfinder,context:Context) {
        if let conn=uiView.preview.connection,conn.isVideoOrientationSupported {conn.videoOrientation = .portrait}
    }
}
