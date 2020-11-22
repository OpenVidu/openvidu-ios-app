//
//  OpenViduController.swift
//  WebRTCapp
//
//  Created by Dario Pacchi on 16/06/2020.
//  Copyright © 2020 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import UIKit
import WebRTC

class OpenViduVideoVC : UIViewController {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var localVideoView: RTCMTLVideoView!
    @IBOutlet weak var closeButton: UIButton!
    @IBOutlet weak var previewHeight: NSLayoutConstraint!
    @IBOutlet weak var previewWidth: NSLayoutConstraint!
    @IBOutlet weak var previewTrailing: NSLayoutConstraint!
    @IBOutlet weak var previewBottom: NSLayoutConstraint!
    @IBOutlet weak var uiLayerBottom: NSLayoutConstraint!
    @IBOutlet weak var uiLayer: UIView!
    @IBOutlet weak var pauseCameraButton: UIButton!
    @IBOutlet weak var pauseAudioButton: UIButton!
    
    let viewModel = OpenViduVideoVM()
    var camera : RTCCameraVideoCapturer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        animatePreviewWindow(fullscreen: true, animated: false)
        
        //Camera
        AVCaptureDevice.requestAccess(for: AVMediaType.video) { response in
            if response {
                print("Camera permission granted!")
            } else {
                
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(routeChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        
        if #available(iOS 11.0, *) {
            collectionView.contentInsetAdjustmentBehavior = .never
        } else {
            // Fallback on earlier versions
        }

        viewModel.connect()
        viewModel.onSocket = {[weak self] (connected, error) in
            
            if error != nil  {
                self?.dismiss(animated: true)
                return
            }
            
            if connected {
                self?.viewModel.createMediaSenders()
                self?.startCapureLocalVideo(position: .front)
            } else {
                self?.dismiss(animated: true)
            }
        }
        viewModel.onUpdate = {[weak self] in
            self?.reloadData()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    //MARK: - Actions
    
    @IBAction func closeButtonTapped(_ sender: UIButton) {
        viewModel.disconnect()
        dismiss(animated: true, completion: nil)
    }
    
    @IBAction func switchCameraButtonTapped(_ sender: Any) {
        let position : AVCaptureDevice.Position = viewModel.frontCameraActive ? .back : .front
        self.startCapureLocalVideo(position: position)
        viewModel.frontCameraActive = !viewModel.frontCameraActive
    }
    
    @IBAction func toggleVideoButtonTapped(_ sender: Any) {
        viewModel.toggleVideo()
        updateButtons()
    }
    
    @IBAction func toggleAudioButtonTapped(_ sender: Any) {
        viewModel.toggleAudio()
        updateButtons()
    }
    //MARK: - Reload
    
    func reloadData () {
        animatePreviewWindow(fullscreen: false, animated: true)
        collectionView.reloadData()
    }
    
    func updateButtons () {

        let colorOn = UIColor.init(white: 0.8, alpha: 0.8)
        let colorOff = UIColor.init(white: 0.5, alpha: 0.8)
        
        pauseCameraButton.backgroundColor = viewModel.videoOn ? colorOff : colorOn
        pauseAudioButton.backgroundColor = viewModel.audioOn ? colorOff : colorOn

    }
    
    //MARK: - Animations
    
    func animatePreviewWindow(fullscreen: Bool, animated: Bool) {
        
        let animationTime = animated ? 0.3 : 0.0
        
        UIView.animate(withDuration: animationTime) {[weak self] in
            if (fullscreen) {
                self?.localVideoView.layer.cornerRadius = 0
                self?.previewWidth.constant = self?.view.bounds.size.width ?? 0
                self?.previewHeight.constant = self?.view.bounds.size.height ?? 0
                self?.previewTrailing.constant = 0
                self?.previewBottom.constant = -(self?.uiLayer.bounds.size.height ?? 0)
            } else {
                self?.localVideoView.layer.cornerRadius = 8
                self?.previewWidth.constant = 110
                self?.previewHeight.constant = 140
                self?.previewTrailing.constant = 20
                self?.previewBottom.constant = 0
            }
            self?.view.setNeedsLayout()
            self?.view.layoutIfNeeded()
        }
    }
    
    //MARK: - Video
    
    func startCapureLocalVideo(position : AVCaptureDevice.Position) {
                
        guard let stream = self.viewModel.peersService.localPeer!.localStreams.first ,let capturer = self.viewModel.videoCapturer as? RTCCameraVideoCapturer else {
           return
        }
        
        guard let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == position }),
            
            // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
            
            // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
                return
        }
                
        capturer.stopCapture()
        capturer.startCapture(with: frontCamera,
                              format: format,
                              fps: Int(fps.maxFrameRate))
        
        
        stream.videoTracks.first?.add(localVideoView)
    }
    
    @objc private func routeChange(_ n: Notification) {
        
        guard let info = n.userInfo,
            let value = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: value) else {
                return
        }
        switch reason {
        case .categoryChange: try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        default: break
        }
    }
    
}

extension OpenViduVideoVC : UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewModel.participants.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "OpenViduParticipantCell", for: indexPath) as! OpenViduParticipantCell
        cell.loadWith(participant: viewModel.participants[indexPath.row])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        let screenSize = UIScreen.main.bounds.size
        let count = viewModel.participants.count
        
        switch count {
        case 1:
            return screenSize
        case 2:
            return CGSize.init(width: screenSize.width, height: screenSize.height/2)
        case 3,4:
            return CGSize.init(width: screenSize.width/2, height: screenSize.height/2)
        case 5,6:
            return CGSize.init(width: screenSize.width/2, height: screenSize.height/3)
        case 7,8:
            return CGSize.init(width: screenSize.width/2, height: screenSize.height/4)
        default:
            return CGSize.init(width: screenSize.width/2, height: screenSize.height/4)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return .zero
    }
    
}
