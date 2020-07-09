//
//  OpenVidu.swift
//  Openvidu Swift
//
//  Created by Dario Pacchi on 09/07/2020.
//  Copyright © 2020 Dario Pacchi. All rights reserved.
//

import Foundation
import UIKit

class OpenVidu {
    
    static func loadVideoController (participantName : String, sessionId: String, serverUrl: String? = nil, openviduSecret: String? = nil, openviduUsername : String? = nil) -> OpenViduVideoVC? {
        
        let storyboard = UIStoryboard(name: "Openvidu", bundle: nil)
        guard let vc = storyboard.instantiateViewController(withIdentifier: "OpenViduVideoVC") as? OpenViduVideoVC else {
            return nil
        }
        vc.modalPresentationStyle = .currentContext

        vc.viewModel.participantName = participantName
        vc.viewModel.session = sessionId
        
        if let url = serverUrl {
            vc.viewModel.baseUrl = url
        }
        
        if let secret = openviduSecret {
            vc.viewModel.secret = secret
        }
        
        if let username = openviduUsername {
            vc.viewModel.username = username
        }
        
        return vc
    }
    
}
