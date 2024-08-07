import Foundation
import Starscream

class WebSocketManager: ObservableObject, WebSocketDelegate {
    private var socket: WebSocket?
    @Published var isConnected = false
    
    var onAudioReceived: ((String) -> Void)?
    var onAssistantMessageReceived: ((String) -> Void)?
    private let authenticator: HumeAuthenticator
    private var sampleRate: Double?
    
    init(apiKey: String, secretKey: String, host: String = "api.hume.ai") {
        self.authenticator = HumeAuthenticator(apiKey: apiKey, secretKey: secretKey, host: host)
    }
    
    func connect(sampleRate: Double) {
        self.sampleRate = sampleRate
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        authenticator.fetchAccessToken { result in
            switch result {
            case .success(let accessToken):
                let urlString = "wss://\(self.authenticator.host)/v0/assistant/chat?access_token=\(accessToken)"
                guard let url = URL(string: urlString) else {
                    print("WebSocketManager: Invalid URL")
                    return
                }
                
                var request = URLRequest(url: url)
                request.timeoutInterval = 5
                
                self.socket = WebSocket(request: request)
                self.socket?.delegate = self
                self.socket?.connect()
                print("WebSocketManager: Attempting to connect to WebSocket")
                
            case .failure(let error):
                print("WebSocketManager: Failed to fetch access token: \(error.localizedDescription)")
            }
        }
    }
    
    func disconnect() {
        socket?.disconnect()
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
    
    func sendSessionSettings() {
        guard let sampleRate = self.sampleRate else {
            print("WebSocketManager: Sample rate not set")
            return
        }
        
        let settings: [String: Any] = [
            "type": "session_settings",
            "audio": [
                "encoding": "linear16",
                "sample_rate": sampleRate,
                "channels": 1
            ]
        ]
        sendJSONMessage(settings)
        print("WebSocketManager: Sent session settings")
    }
    
    func sendAudioData(_ base64AudioData: String) {
        let jsonMessage: [String: Any] = [
            "type": "audio_input",
            "data": base64AudioData
        ]
        
        sendJSONMessage(jsonMessage)
        print("WebSocketManager: Sent audio chunk of size: \(base64AudioData.count) characters")
    }
    
    func sendTextInput(_ text: String) {
        let jsonMessage: [String: Any] = [
            "type": "text_input",
            "data": text
        ]
        sendJSONMessage(jsonMessage)
    }
    
    private func sendJSONMessage(_ message: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: message)
            
            socket?.write(data: jsonData)
            print("WebSocketManager: Successfully sent JSON message")
        } catch {
            print("WebSocketManager: Failed to encode JSON: \(error)")
        }
    }
    
    // MARK: - WebSocketDelegate Methods
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(_):
            print("WebSocketManager: WebSocket connected")
            DispatchQueue.main.async {
                self.isConnected = true
                self.sendSessionSettings()
            }
        case .disconnected(let reason, let code):
            print("WebSocketManager: WebSocket disconnected: \(reason) with code: \(code)")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        case .text(let string):
            print("WebSocketManager: Received text message: \(string)")
            handleMessage(string)
        case .binary(let data):
            print("WebSocketManager: Received binary data: \(data.count) bytes")
        case .pong(_), .ping(_), .viabilityChanged(_), .reconnectSuggested(_):
            break
        case .cancelled:
            print("WebSocketManager: WebSocket cancelled")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        case .error(let error):
            print("WebSocketManager: WebSocket error: \(error?.localizedDescription ?? "Unknown error")")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        case .peerClosed:
            print("WebSocketManager: Peer closed the connection")
            DispatchQueue.main.async {
                self.isConnected = false
            }
        }
    }
    
    private func handleMessage(_ message: String) {
        guard let data = message.data(using: .utf8) else {
            print("Failed to convert message to data")
            return
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                if let type = json["type"] as? String {
                    switch type {
                    case "audio_output":
                        if let audioBase64 = json["data"] as? String {
                            print("Received audio output of length: \(audioBase64.count)")
                            DispatchQueue.main.async {
                                self.onAudioReceived?(audioBase64)
                            }
                        } else {
                            print("Audio data not found in audio_output message")
                        }
                    case "assistant_message":
                        if let message = json["message"] as? [String: Any],
                           let content = message["content"] as? String {
                            print("Received assistant message: \(content)")
                            DispatchQueue.main.async {
                                self.onAssistantMessageReceived?(content)
                            }
                        } else {
                            print("Content not found in assistant_message")
                        }
                    default:
                        print("Received message of unknown type: \(type)")
                    }
                } else {
                    print("Message type not found in JSON")
                }
            } else {
                print("Failed to parse JSON from message")
            }
        } catch {
            print("Error parsing JSON: \(error)")
        }
    }
}
