//
//  ViewController.swift
//  Openvidu Swift
//
//  Created by Dario Pacchi on 06/07/2020.
//  Copyright © 2020 Dario Pacchi. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var sessionIdTextField: UITextField!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        sessionIdTextField.text = ""
    }

    @IBAction func connectTapped(_ sender: Any) {
        
        guard let username = usernameTextField.text, let session = sessionIdTextField.text else {
            return
        }

        guard let vc = OpenVidu.loadVideoController(participantName: username, sessionId: session) else {
            return
        }
        
        present(vc, animated: true, completion: nil)
        
    }
}

