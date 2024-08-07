import AVFoundation
import Foundation

class AudioManager: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let webSocketManager: WebSocketManager
    
    @Published var isRecording = false
    
    private var _sampleRate: Double = 0
    private let bufferSize: AVAudioFrameCount = 4096
    private var audioBuffer = Data()
    
    var sampleRate: Double {
        return _sampleRate
    }
    
    init(webSocketManager: WebSocketManager) {
        self.webSocketManager = webSocketManager
        setupAudioSession()
        setupAudioEngine()
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try audioSession.setActive(true)
            _sampleRate = audioSession.sampleRate
            print("AudioManager: Audio session set up successfully. Sample rate: \(_sampleRate)")
        } catch {
            print("AudioManager: Failed to set up audio session: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("AudioManager: Failed to create audio engine")
            return
        }
        
        inputNode = audioEngine.inputNode
        let inputFormat = inputNode?.inputFormat(forBus: 0)
        print("AudioManager: Input format - \(inputFormat?.description ?? "Unknown")")
        
        inputNode?.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer, when) in
            self?.processBuffer(buffer)
        }
        
        audioEngine.prepare()
    }
    
    func startRecording() {
        guard let audioEngine = audioEngine else {
            print("AudioManager: Audio engine not initialized")
            return
        }
        
        if audioEngine.isRunning {
            print("AudioManager: Audio engine is already running")
            return
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            print("AudioManager: Started recording")
        } catch {
            print("AudioManager: Could not start audio engine: \(error)")
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        inputNode?.removeTap(onBus: 0)
        isRecording = false
        print("AudioManager: Stopped recording")
    }
    
    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            print("AudioManager: Could not get float channel data")
            return
        }
        
        let channelDataPtr = channelData[0]
        let length = Int(buffer.frameLength)
        
        var int16Samples = [Int16]()
        for i in 0..<length {
            let sample = channelDataPtr[i]
            let int16Sample = Int16(max(-32768, min(32767, sample * 32767)))
            int16Samples.append(int16Sample)
        }
        
        let newAudioData = Data(bytes: int16Samples, count: length * 2)
        audioBuffer.append(newAudioData)
        
        let bytesPerChunk = Int(_sampleRate * 0.1) * 2 // 100ms chunks
        while audioBuffer.count >= bytesPerChunk {
            let chunkData = audioBuffer.prefix(bytesPerChunk)
            sendAudioChunk(chunkData)
            audioBuffer.removeFirst(bytesPerChunk)
        }
    }
    
    private func sendAudioChunk(_ chunkData: Data) {
        let base64Chunk = chunkData.base64EncodedString()
        
        print("AudioManager: Sending audio chunk:")
        print("  Size: \(chunkData.count) bytes")
        print("  Base64 length: \(base64Chunk.count) characters")
        
        webSocketManager.sendAudioData(base64Chunk)
    }

    func sendTextInput() {
        webSocketManager.sendTextInput("Hi, How are you doing?")
    }
}
