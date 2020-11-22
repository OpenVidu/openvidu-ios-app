//
//  WebSocketService.swift
//  WebRTCapp
//
//  Created by Dario Pacchi on 16/06/2020.
//  Copyright © 2020 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import Starscream
import WebRTC

class WebSocketService: WebSocketDelegate {
    
    let JSON_RPCVERSION = "2.0"
    let useSSL = true
    var socket: WebSocket
    weak var pingTimer: Timer?
    var id = 0
    var url: String
    var sessionName: String
    var participantName: String
    var localOfferParams: [String: String]?
    var iceCandidatesParams: [[String:String]]?
    var userId: String?
    var remoteParticipantId: String?
    var participants: [String: RemoteParticipant]
    var localPeer: RTCPeerConnection?
    var peersManager: PeersService
    var token: String
    
    var iceServers = [RTCIceServer]()
    
    var onSocketConnected : (()->())?
    var onParticipantsChanged : (([RemoteParticipant])->())?
    var onSocketDisconnected : (()->())?
    
    //MARK: - Init
    
    init(baseUrl: String, sessionName: String, participantName: String, peersManager: PeersService, openViduToken: OpenViduToken) {
        
        self.url = baseUrl.components(separatedBy: "?").first?.appending("/openvidu") ?? ""
        self.sessionName = sessionName
        self.participantName = participantName
        self.peersManager = peersManager
        self.localPeer = self.peersManager.localPeer
        self.iceCandidatesParams = []
        self.token = openViduToken.token
        self.participants = [String: RemoteParticipant]()
                
        let request = URLRequest(url: URL(string: self.url)!)
        socket = WebSocket(request: request)
        socket.delegate = self
        
        self.createTURNServers(openViduToken: openViduToken)

        socket.connect()
            
    }

    deinit {
        print("Socket Service deallocated")
    }
    
    //MARK: - Turn Servers
    
    func createTURNServers (openViduToken: OpenViduToken) {
        
        let turnServer = openViduToken.getQueryParameter(parameter: "coturnIp")
        let turnUsername = openViduToken.getQueryParameter(parameter: "turnUsername")
        let turnCredential = openViduToken.getQueryParameter(parameter: "turnCredential")
    
        var iceServers = [RTCIceServer]()
        
        let stunServer = RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        let iceServer = RTCIceServer(urlStrings: ["stun:" + turnServer + ":3478"])
        let turn = RTCIceServer.init(urlStrings: ["turn:" + turnServer + ":3478"], username: turnUsername, credential: turnCredential)
        let turn2 = RTCIceServer.init(urlStrings: ["turn:" + turnServer + ":3478?transport=tcp"], username: turnUsername, credential: turnCredential)

        iceServers.append(stunServer)
        iceServers.append(iceServer)
        iceServers.append(turn)
        iceServers.append(turn2)

        self.iceServers = iceServers
    }
    
    
    //MARK: - Websocket protocols
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            print("websocket is connected: \(headers)")
            pingMessageHandler()
            websocketDidConnect(socket: client)
        case .disconnected(let reason, let code):
            websocketDidDisconnect(socket: client, error: nil)
            print("websocket is disconnected: \(reason) with code: \(code)")
        case .text(let string):
            print("Received text: \(string)")
            websocketDidReceiveMessage(socket: client, text: string)
        case .binary(let data):
            print("Received data: \(data.count)")
            websocketDidReceiveData(socket: client, data: data)
        case .ping(_):
            break
        case .pong(_):
            break
        case .viabilityChanged(let bool):
            print("Viability Changed: \(bool)")
            break
        case .reconnectSuggested(_):
            break
        case .cancelled:
            websocketDidDisconnect(socket: client, error: nil)
            break
        case .error(let error):
            print("Error: \(String(describing: error?.localizedDescription))")
        }
    }
    
    func websocketDidConnect(socket: WebSocketClient) {
        
        print("Connected")
        //        pingMessageHandler()
        var joinRoomParams: [String: String] = [:]
        joinRoomParams["recorder"] = "false"
        joinRoomParams["platform"] = "iOS"
        joinRoomParams[JSONConstants.Metadata] = "{\"clientData\": \"" + "\(self.participantName)" + "\"}"
        joinRoomParams["secret"] = ""
        joinRoomParams["session"] = sessionName
        joinRoomParams["token"] = token
        sendJson(method: "joinRoom", params: joinRoomParams)
        if localOfferParams != nil {
            sendJson(method: "publishVideo",params: localOfferParams!)
        }
        onSocketConnected?()
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        print("Disconnect: " + error.debugDescription)
        onSocketDisconnected?()
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        //        print("Recieved message: " + text)
        let data = text.data(using: .utf8)!
        do {
            let json: [String: Any] = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as! [String : Any]
            
            if json[JSONConstants.Result] != nil {
                handleResult(json: json)
            } else {
                handleMethod(json: json)
            }
            
        } catch let error as NSError {
            print("ERROR parsing JSON: ", error)
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("Received data: " + data.description)
    }
    
    //MARK: - Send
    
    func sendJson(method: String, params: [String: String]) {
        
        let json: NSMutableDictionary = NSMutableDictionary()
        json.setValue(method, forKey: JSONConstants.Method)
        json.setValue(id, forKey: JSONConstants.Id)
        id += 1
        json.setValue(params, forKey: JSONConstants.Params)
        json.setValue(JSON_RPCVERSION, forKey: JSONConstants.JsonRPC)
        let jsonData: NSData
        do {
            jsonData = try JSONSerialization.data(withJSONObject: json, options: JSONSerialization.WritingOptions()) as NSData
            let jsonString = NSString(data: jsonData as Data, encoding: String.Encoding.utf8.rawValue)! as String
            //            print("Sending = \(jsonString)")
            socket.write(string: jsonString)
        } catch _ {
            print ("JSON Failure")
        }
    }
    
    //MARK: - Receive
    
    func handleResult(json: [String: Any]) {
        let result: [String: Any] = json[JSONConstants.Result] as! [String: Any]
        if result[JSONConstants.SdpAnswer] != nil {
            saveAnswer(json: result)
        } else if result[JSONConstants.SessionId] != nil {
            if result[JSONConstants.Value] != nil {
                let value = result[JSONConstants.Value]  as! [[String:Any]]
                if !value.isEmpty {
                    addParticipantsAlreadyInRoom(result: result)
                }
                self.userId = result[JSONConstants.Id] as? String
                for var iceCandidate in iceCandidatesParams! {
                    iceCandidate["endpointName"] = self.userId
                    sendJson(method: "onIceCandidate", params:  iceCandidate)
                }
            }
        } else if result[JSONConstants.Value] != nil {
            print("pong")
        } else {
            print("Unrecognized")
        }
    }
    
    //MARK: - Participants
    
    func handleMethod(json: Dictionary<String,Any>) {
        if json[JSONConstants.Params] != nil {
            let method = json[JSONConstants.Method] as! String
            let params = json[JSONConstants.Params] as! Dictionary<String, Any>
            print("method : * " + method)
            switch method {
            case JSONConstants.IceCandidate:
                iceCandidateMethod(params: params)
            case JSONConstants.ParticipantJoined:
                participantJoinedMethod(params: params)
            case JSONConstants.ParticipantPublished:
                participantPublished(params: params)
            case JSONConstants.ParticipantLeft:
                participantLeft(params: params)
            default:
                print("Error handleMethod, " + "method '" + method + "' is not implemented")
            }
        }
    }
    
    func addParticipantsAlreadyInRoom(result: [String: Any]) {
        
        let localmetadataString = result[JSONConstants.Metadata] as! String
        let localName =  getClientName(metadataString: localmetadataString)
        
        let values = result[JSONConstants.Value] as! [[String: Any]]
        for participant in values {
//            let participant = values.last!
        
            print(participant[JSONConstants.Id]!)
            let metadataString = participant[JSONConstants.Metadata] as! String
            let name : String? = getClientName(metadataString: metadataString)
            
            guard Array(self.participants.values).filter({$0.participantName == name}).count == 0 && name != localName  else {
                continue
            }
            
            self.remoteParticipantId = participant[JSONConstants.Id]! as? String
            let remoteParticipant = RemoteParticipant()
            remoteParticipant.id = participant[JSONConstants.Id] as? String
            remoteParticipant.participantName = name
            self.participants[remoteParticipant.id!] = remoteParticipant
            self.peersManager.createRemotePeerConnection(remoteParticipant: remoteParticipant)
            let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
            let sdpConstraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil)
            
            remoteParticipant.peerConnection?.delegate = self.peersManager
//            self.peersManager.remotePeer!.delegate = self.peersManager

            if let streams = participant["streams"] as? NSArray, let stream = streams.firstObject as? NSDictionary, let streamId = stream["id"] as? String {
                
                remoteParticipant.peerConnection!.offer(for: sdpConstraints, completionHandler: {(sessionDescription, error) in
                    print("Remote Offer: " + error.debugDescription)
                    self.participants[remoteParticipant.id!]!.peerConnection!.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                        print("Remote Peer Local Description set " + error.debugDescription)
                    })
                    var remoteOfferParams: [String:String] = [:]
                    remoteOfferParams["sdpOffer"] = sessionDescription!.sdp
                    remoteOfferParams["sender"] = streamId
                    self.sendJson(method: "receiveVideoFrom", params: remoteOfferParams)
                })
            }
        }
    }
    
    func getClientName (metadataString : String) -> String? {
        var name : String? = nil
        let data = metadataString.data(using: .utf8)!
        do {
            if let metadata = try JSONSerialization.jsonObject(with: data, options : .allowFragments) as? Dictionary<String,Any>
            {
                name = metadata["clientData"] as? String
            }
        } catch let error as NSError {
            print(error)
        }
        return name
    }
    
    func participantJoinedMethod(params: Dictionary<String, Any>) {
        
        let metadataString = params[JSONConstants.Metadata] as! String
        let name = getClientName(metadataString: metadataString)
        
        guard Array(self.participants.values).filter({$0.participantName == name}).count == 0 /*&& name != localName*/  else {
            return
        }
        
        let remoteParticipant = RemoteParticipant()
        remoteParticipant.id = params[JSONConstants.Id] as? String
        self.participants[params[JSONConstants.Id] as! String] = remoteParticipant
        remoteParticipant.participantName = name
        self.peersManager.createRemotePeerConnection(remoteParticipant: remoteParticipant)
    }
    
    func participantPublished(params: Dictionary<String, Any>) {
        
        self.remoteParticipantId = params[JSONConstants.Id] as? String
        print("ID: " + remoteParticipantId!)
        guard let remoteParticipantPublished = participants[remoteParticipantId!] else {
            return
        }
        let mandatoryConstraints = ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"]
        
        if let streams = params["streams"] as? NSArray, let stream = streams.firstObject as? NSDictionary, let streamId = stream["id"] as? String {
            
            remoteParticipantPublished.peerConnection!.offer(for: RTCMediaConstraints.init(mandatoryConstraints: mandatoryConstraints, optionalConstraints: nil), completionHandler: { (sessionDescription, error) in
                remoteParticipantPublished.peerConnection!.setLocalDescription(sessionDescription!, completionHandler: {(error) in
                    print("Remote Peer Local Description set")
                })
                var remoteOfferParams:  [String: String] = [:]
                remoteOfferParams["sdpOffer"] = sessionDescription!.description
                remoteOfferParams["sender"] = streamId
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.sendJson(method: "receiveVideoFrom", params: remoteOfferParams)
//                }
            })
            remoteParticipantPublished.peerConnection?.delegate = self.peersManager
//            self.peersManager.remotePeer!.delegate = self.peersManager
        }
    }
    
    func participantLeft(params: Dictionary<String, Any>) {
        
        print("participants", participants)
        print("params", params)
        let participantId = params["connectionId"] as! String
        participants[participantId]!.peerConnection!.close()
        participants.removeValue(forKey: participantId)
        onParticipantsChanged?(getAllParticipants())
    }
    
    //MARK: - Ice Candidate
    
    func iceCandidateMethod(params: Dictionary<String, Any>) {
        if (params["endpointName"] as? String == userId) {
            saveIceCandidate(json: params, endPointName: nil)
        } else {
            saveIceCandidate(json: params, endPointName: params["endpointName"] as? String)
        }
    }
    
    func saveIceCandidate(json: Dictionary<String, Any>, endPointName: String?) {
        let iceCandidate = RTCIceCandidate(sdp: json["candidate"] as! String, sdpMLineIndex: json["sdpMLineIndex"] as! Int32, sdpMid: json["sdpMid"] as? String)
        if (endPointName == nil || participants[endPointName!] == nil) {
            self.localPeer = self.peersManager.localPeer
            self.localPeer!.add(iceCandidate)
        } else {
            participants[endPointName!]!.peerConnection!.add(iceCandidate)
        }
    }
    
    func addIceCandidate(iceCandidateParams: [String: String]) {
        iceCandidatesParams!.append(iceCandidateParams)
    }
    
    //MARK: - Callback
    
    func saveAnswer(json: [String:Any]) {
        
        let sessionDescription = RTCSessionDescription(type: RTCSdpType.answer, sdp: json[JSONConstants.SdpAnswer] as! String)
        if localPeer == nil {
            self.localPeer = self.peersManager.localPeer
        }
        if (localPeer!.remoteDescription != nil) {
            participants[remoteParticipantId!]!.peerConnection!.setRemoteDescription(sessionDescription, completionHandler: {[weak self] (error) in
                if self != nil {
                    self!.onParticipantsChanged?(self?.getAllParticipants() ?? [])
                }
            })
        } else {
            localPeer!.setRemoteDescription(sessionDescription, completionHandler: {(error) in
                print("Local Peer Remote Description set: " + error.debugDescription)
            })
        }
    }
    
    //MARK: - Participants
    
    func getAllParticipants() -> [RemoteParticipant]{
        return Array(participants.values)
    }
    
    //MARK: - Disconnect
    
    func disconnect() {
        sendJson(method: "leaveRoom", params: [:])
        pingTimer?.invalidate()
        pingTimer = nil
    }
    
    //MARK: - Utils
    
    func pingMessageHandler() {
        pingTimer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(WebSocketService.doPing), userInfo: nil, repeats: true)
        doPing()
    }
    
    @objc func doPing() {
        var pingParams: [String: String] = [:]
        pingParams["interval"] = "5000"
        sendJson(method: "ping", params: pingParams)
        socket.write(ping: Data())
    }
}
