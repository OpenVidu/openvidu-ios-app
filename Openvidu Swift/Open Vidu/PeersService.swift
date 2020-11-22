//
//  PeersService.swift
//  WebRTCapp
//
//  Created by Dario Pacchi on 16/06/2020.
//  Copyright © 2020 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import WebRTC
import Starscream

class PeersService: NSObject {
    
    weak var webSocketListener: WebSocketService?
    
    var localPeer: RTCPeerConnection?
    var peerConnectionFactory: RTCPeerConnectionFactory?
    var connectionConstraints: RTCMediaConstraints?
    var webSocket: WebSocket?
    var localVideoTrack: RTCVideoTrack?
    var localAudioTrack: RTCAudioTrack?
    
    deinit {
        print("Peers Service deallocated")
    }
    
    func setWebSocketAdapter(webSocketAdapter: WebSocketService) {
        self.webSocketListener = webSocketAdapter
    }
    
    func start() {
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
        
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ]
        let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        createLocalPeerConnection(sdpConstraints: sdpConstraints)
    }
    
    func createLocalPeerConnection(sdpConstraints: RTCMediaConstraints) {
        
        let config = RTCConfiguration()
        config.bundlePolicy = .maxCompat
        //config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        if let webSocketListener = webSocketListener {
            config.iceServers = webSocketListener.iceServers
        }
        config.rtcpMuxPolicy = .require
        
        localPeer = peerConnectionFactory!.peerConnection(with: config, constraints: sdpConstraints, delegate: self)
    }
    
    func createLocalOffer(mediaConstraints: RTCMediaConstraints) {
        localPeer!.offer(for: mediaConstraints, completionHandler: { (sessionDescription, error) in
            self.localPeer!.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                print("Local Peer local Description set: " + error.debugDescription)
            })
            var localOfferParams: [String:String] = [:]
            localOfferParams["audioActive"] = "true"
            localOfferParams["videoActive"] = "true"
            localOfferParams["doLoopback"] = "false"
            localOfferParams["hasAudio"] = "true"
            localOfferParams["hasVideo"] = "true"
            
            localOfferParams["frameRate"] = "30"
            localOfferParams["typeOfVideo"] = "CAMERA"
            localOfferParams["videoDimensions"] = "{\"width\":640,\"height\":480}"
            
            localOfferParams["sdpOffer"] = sessionDescription!.sdp
            if (self.webSocketListener!.id) > 1 {
                self.webSocketListener!.sendJson(method: "publishVideo", params: localOfferParams)
            } else {
                self.webSocketListener!.localOfferParams = localOfferParams
            }
        })
    }
    
    func createRemotePeerConnection(remoteParticipant: RemoteParticipant) {
        
        print("[PEERS SERVICE] - Create remote participant: \(remoteParticipant.participantName ?? "---")")
        let mandatoryConstraints = [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": "true"
        ]
        let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
        
        let config = RTCConfiguration()
        config.tcpCandidatePolicy = .enabled
        config.bundlePolicy = .maxBundle
        config.rtcpMuxPolicy = .negotiate
        config.continualGatheringPolicy = .gatherContinually
        config.keyType = .ECDSA
        config.activeResetSrtpParams = true
        config.sdpSemantics = .unifiedPlan
        if let webSocketListener = webSocketListener {
            config.iceServers = webSocketListener.iceServers
        }
        
        remoteParticipant.peerConnection = (peerConnectionFactory?.peerConnection(with: config, constraints: sdpConstraints, delegate: self))!
    }
}

extension PeersService: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        if peerConnection == self.localPeer {
            print("local peerConnection new signaling state: \(stateChanged.rawValue)")
        } else {
            print("remote peerConnection new signaling state: \(stateChanged.rawValue)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if peerConnection == self.localPeer {
            print("local peerConnection did add stream")
        } else {
            print("remote peerConnection did add stream")
            
            if (stream.audioTracks.count > 1 || stream.videoTracks.count > 1) {
                print("Weird looking stream")
            }
            
            let participant = webSocketListener?.getAllParticipants().filter{$0.peerConnection == peerConnection}.first
            participant?.mediaStream = stream
            participant?.audioTrack = stream.audioTracks.first
            participant?.videoTrack = stream.videoTracks.first
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        if peerConnection == self.localPeer {
            print("local peerConnection did remove stream")
        } else {
            print("remote peerConnection did remove stream")
        }
        
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        if peerConnection == self.localPeer {
            print("local peerConnection should negotiate")
        } else {
            print("remote peerConnection should negotiate")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        if peerConnection == self.localPeer {
            print("local peerConnection new connection state: \(newState.rawValue)")
        } else {
            print("remote peerConnection new connection state: \(newState.rawValue)")
        }
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if peerConnection == self.localPeer {
            print("local peerConnection new gathering state: \(newState.rawValue)")
        } else {
            print("remote peerConnection new gathering state: \(newState.rawValue)")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        if peerConnection == self.localPeer {
            var iceCandidateParams: [String: String] = [:]
            iceCandidateParams["sdpMid"] = candidate.sdpMid
            iceCandidateParams["sdpMLineIndex"] = String(candidate.sdpMLineIndex)
            iceCandidateParams["candidate"] = String(candidate.sdp)
            if self.webSocketListener!.userId != nil {
                iceCandidateParams["endpointName"] =  self.webSocketListener!.userId
                self.webSocketListener!.sendJson(method: "onIceCandidate", params: iceCandidateParams)
            } else {
                self.webSocketListener!.addIceCandidate(iceCandidateParams: iceCandidateParams)
            }
            print("NEW local ice candidate")
        } else {
            
            let participant = webSocketListener?.getAllParticipants().filter{$0.peerConnection == peerConnection}.first
            
            var iceCandidateParams: [String: String] = [:]
            iceCandidateParams["sdpMid"] = candidate.sdpMid
            iceCandidateParams["sdpMLineIndex"] = String(candidate.sdpMLineIndex)
            iceCandidateParams["candidate"] = String(candidate.sdp)
            iceCandidateParams["endpointName"] =  participant?.id
            self.webSocketListener!.sendJson(method: "onIceCandidate", params: iceCandidateParams)
            print("NEW remote ice candidate")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        
        if peerConnection == self.localPeer {
            print("local peerConnection did open data channel")
        } else {
            print("remote peerConnection did open data channel")
        }
    }
}
