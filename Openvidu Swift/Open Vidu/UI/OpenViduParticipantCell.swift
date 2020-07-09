//
//  OpenViduParticipantCell.swift
//  WebRTCapp
//
//  Created by Dario Pacchi on 16/06/2020.
//  Copyright © 2020 Sergio Paniego Blanco. All rights reserved.
//

import Foundation
import UIKit
import WebRTC

class OpenViduParticipantCell: UICollectionViewCell {
    
    @IBOutlet weak var videoView: RTCMTLVideoView!
    @IBOutlet weak var partecipantLabel: UILabel!
    
    func loadWith(participant: RemoteParticipant) {
        
        partecipantLabel.text = participant.participantName
        participant.videoTrack?.add(videoView)
//        participant.audioTrack?.source.volume = 7
    }
    
}
