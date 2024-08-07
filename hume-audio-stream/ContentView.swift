import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var audioManager: AudioManager
    @StateObject private var webSocketManager: WebSocketManager
    @State private var isRecording = false
    @State private var messages: [String] = []
    @State private var logMessages: [String] = []
    
    init() {
        let wsManager = WebSocketManager(
            apiKey: "",
            secretKey: "",
            host: "api.hume.ai"
        )
        _webSocketManager = StateObject(wrappedValue: wsManager)
        _audioManager = StateObject(wrappedValue: AudioManager(webSocketManager: wsManager))
    }
    
    var body: some View {
        VStack {
            connectionStatusView
            
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                            .padding(.vertical, 5)
                    }
                }
            }
            
            Button(action: toggleRecording) {
                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .padding()
                    .background(isRecording ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Divider()
            
            logView
        }
        .padding()
        .onAppear {
            setupAudioSession()
            connectWebSocket()
        }
    }
    
    private var connectionStatusView: some View {
        HStack {
            Circle()
                .fill(webSocketManager.isConnected ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text(webSocketManager.isConnected ? "Connected" : "Disconnected")
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var logView: some View {
        ScrollView {
            VStack(alignment: .leading) {
                ForEach(logMessages, id: \.self) { log in
                    Text(log)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
        }
        .frame(height: 100)
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            addLog("Failed to set up audio session: \(error)")
        }
    }
    
    private func connectWebSocket() {
        webSocketManager.connect(sampleRate: audioManager.sampleRate)
        webSocketManager.onAssistantMessageReceived = { message in
            DispatchQueue.main.async {
                self.messages.append(message)
                self.addLog("Received assistant message: \(message)")
            }
        }
        webSocketManager.onAudioReceived = { audioBase64 in
            self.addLog("Received audio of length: \(audioBase64.count)")
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            audioManager.stopRecording()
            addLog("Stopped recording")
        } else {
            audioManager.startRecording()
            addLog("Started recording")
        }
        isRecording.toggle()
    }
    
    private func addLog(_ message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        DispatchQueue.main.async {
            self.logMessages.append(logMessage)
            
            // Keep only the last 100 log messages
            if self.logMessages.count > 100 {
                self.logMessages.removeFirst(self.logMessages.count - 100)
            }
        }
    }
}
