//
//  OpenViduService.swift
//  WebRTCapp
//
//  Created by Dario Pacchi on 16/06/2020.
//  Copyright © 2020 Sergio Paniego Blanco. All rights reserved.
//

import Foundation

class OpenViduService {
    
    static let shared = OpenViduService()
    
    func connectTo(url : String, username: String, password: String, room: String, completion: @escaping (_ token: OpenViduToken?, _ success: Bool, _ error: Error? ) -> Void) {
        
        getRoom(url: url, username: username, password: password, room: room) {[weak self] (success, error, sessionId) in
            
            guard success == true else {
                completion(nil,false,error)
                return
            }
            
            self?.getToken(url: url, username: username, password: password, room: sessionId) { (token, success, error) in
                guard success == true else {
                    completion(nil,false,error)
                    return
                }
                
                completion(token,true,error)
            }
        }
    }
    
    func basicTokenFor(username: String, password: String) -> String {
        
        let bearer = "\(username):\(password)"
        return "Basic \(bearer.toBase64())"
    }
    
    private func getRoom(url : String, username: String, password: String, room: String, completion: @escaping (_ success: Bool, _ error: Error?, _ sessionId: String) -> Void) {
        
        let bearer = basicTokenFor(username: username, password: password)
        
        let uri = URL(string: url.appending("/sessions/"))!
        var request = URLRequest(url: uri)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(bearer, forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        let json = "{\"customSessionId\": \"\(room)\"}"
        request.httpBody = json.data(using: .utf8)
        
        var responseString = ""
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            guard let data = data, error == nil else {                                                 // check for fundamental networking error
                print("⚠️ [OpenVidu] error=\(String(describing: error)), Status Code: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(false, error, room)
                return
            }
            guard let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 else {           // check for http errors
                print("⚠️ [OpenVidu] error=\(String(describing: error)), Status Code: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(true, error, room)
                return
            }
            responseString = String(data: data, encoding: .utf8)!
            print("[OpenVidu] \(responseString)")
            
            let jsonData = responseString.data(using: .utf8)!
            var sessionId = room
            do {
                let json = try JSONSerialization.jsonObject(with: jsonData, options : .allowFragments) as? Dictionary<String,Any>
                sessionId = json!["id"] as! String
            } catch let error as NSError {
                print(error)
            }
            completion(true,nil,sessionId)
        }
        task.resume()
    }
    
    private func getToken(url : String, username: String, password: String, room: String, completion: @escaping (_ token: OpenViduToken?, _ success: Bool, _ error: Error? ) -> Void) {
        
        let bearer = basicTokenFor(username: username, password: password)
        
        let uri = URL(string: url.appending("/tokens/"))!
        var request = URLRequest(url: uri)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.addValue(bearer, forHTTPHeaderField: "Authorization")
        request.httpMethod = "POST"
        let json = "{\"session\": \"" + room + "\"}"
        request.httpBody = json.data(using: .utf8)
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            
            guard let data = data, error == nil else {                                                 // check for fundamental networking error
                print("⚠️ [OpenVidu] error=\(String(describing: error)), Status Code: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(nil, false, error)
                return
            }
            guard let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode == 200 else {           // check for http errors
                print("⚠️ [OpenVidu] error=\(String(describing: error)), Status Code: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                completion(nil, false, error)
                return
            }
            
            let responseString = String(data: data, encoding: .utf8)
            print("responseString = \(String(describing: responseString))")
            let token = try? JSONDecoder().decode(OpenViduToken.self, from: data) as OpenViduToken
            completion(token, true, error)
        }
        task.resume()
    }
}

extension String {

    func fromBase64() -> String? {
        guard let data = Data(base64Encoded: self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func toBase64() -> String {
        return Data(self.utf8).base64EncodedString()
    }

}

// MARK: - OpenViduToken
struct OpenViduToken: Codable {
    let id, session, role, data: String
    let token: String
    
    func getJustSessionId() -> String {
        return token.slice(from: "sessionId=", to: "&") ?? ""
    }
    
    func getJustToken() -> String {
        return token.slice(from: "&token=", to: "&") ?? ""
    }
    
    func getQueryParameter(parameter : String) -> String {
        if let value = token.slice(from: "&\(parameter)=", to: "&") {
            return value
        }
        return token.components(separatedBy: "\(parameter)=").last ?? ""
    }
}

extension String {

    func slice(from: String, to: String) -> String? {

        return (range(of: from)?.upperBound).flatMap { substringFrom in
            (range(of: to, range: substringFrom..<endIndex)?.lowerBound).map { substringTo in
                String(self[substringFrom..<substringTo])
            }
        }
    }
}

