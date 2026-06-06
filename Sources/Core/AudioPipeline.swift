import Foundation
import AVFoundation
import AVFAudio
import Combine
import AudioToolbox
import CoreAudio
import Accelerate

public class AudioPipeline: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    public let id: UUID = UUID()
    public let name: String
    
    // Published State
    @Published public var isEnabled: Bool = false
    @Published public var inputLevel: Float = 0.0
    @Published public var outputGainValue: Float = 1.0 {
        didSet {
            dspEngine.outputGain = outputGainValue
        }
    }
    @Published public var errorMessage: String?
    @Published public var selectedInputDeviceID: String = "" {
        didSet {
            setupCaptureSession()
        }
    }
    @Published public var selectedOutputDeviceID: AudioObjectID = 0 {
        didSet {
            setupPlaybackEngine()
        }
    }
    @Published public var isPlayingTestTone: Bool = false
    
    // Audio Configuration
    private let captureSession = AVCaptureSession()
    private let captureOutput = AVCaptureAudioDataOutput()
    private let processingQueue = DispatchQueue(label: "audio.processing.queue.\(UUID().uuidString)", qos: .userInteractive)
    
    // Playback
    private let engine = AVAudioEngine()
    private var playbackSourceNode: AVAudioSourceNode!
    private var outputNode: AVAudioOutputNode { engine.outputNode }
    private var mainMixer: AVAudioMixerNode { engine.mainMixerNode }
    
    // Buffering and Processing
    private let ringBuffer = RingBuffer(capacity: 48000 * 5)
    private let dspEngine = DeepFilterNetDSP()
    
    // Converter State
    private var inputConverter: AVAudioConverter?
    private var inputPCMBuffer: AVAudioPCMBuffer?
    private var inputBuffer48k: AVAudioPCMBuffer?
    
    public init(name: String = "Pipeline") {
        self.name = name
        super.init()
        
        let bufferRef = ringBuffer
        let dsp = dspEngine
        
        playbackSourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let data = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let count = Int(frameCount)
            
            // 1. Test Tone
            if let self = self, self.isPlayingTestTone {
                for i in 0..<count {
                    data[i] = Float.random(in: -0.1...0.1)
                }
                return noErr
            }
            
            // 2. Latency Management
            let latencyTarget = 2400
            let available = bufferRef.count
            if available > (latencyTarget + count) {
                bufferRef.drop(available - latencyTarget)
            }
            
            // 3. Read from Buffer
            if !bufferRef.read(into: data, count: count) {
                AudioUtils.shared.fillSilence(data, count: count)
                return noErr
            }
            
            // 4. Processing
            var gain: Float = 1.0
            vDSP_vsmul(data, 1, &gain, data, 1, vDSP_Length(frameCount))
            
            if let self = self, self.isEnabled {
                dsp.process(input: data, count: count, output: data)
            }
            
            return noErr
        }
        
        setupPlaybackEngine()
    }
    
    func setupPlaybackEngine() {
        engine.stop()
        engine.reset()
        
        // Output Device
        if selectedOutputDeviceID != 0 {
            var deviceID = selectedOutputDeviceID
            let size = UInt32(MemoryLayout<AudioObjectID>.size)
            AudioUnitSetProperty(outputNode.audioUnit!,
                                 kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global,
                                 0,
                                 &deviceID,
                                 size)
        }
        
        // Attach Source
        engine.attach(playbackSourceNode)
        
        // Connect
        engine.connect(playbackSourceNode, to: mainMixer, format: AudioUtils.shared.processingFormat)
        engine.connect(mainMixer, to: outputNode, format: nil)
        
        do {
            try engine.start()
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Engine Error: \(error)"
            }
        }
    }
    
    func setupCaptureSession() {
        captureSession.stopRunning()
        captureSession.beginConfiguration()
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }
        
        do {
            guard let device = AVCaptureDevice(uniqueID: selectedInputDeviceID) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Device not found: \(self.selectedInputDeviceID)"
                }
                captureSession.commitConfiguration()
                return
            }
            
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            if captureSession.canAddOutput(captureOutput) {
                captureSession.addOutput(captureOutput)
                captureOutput.setSampleBufferDelegate(self, queue: processingQueue)
            }
            
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Capture Setup Error: \(error)"
            }
        }
        
        captureSession.commitConfiguration()
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else { return }
        
        // 1. Determine Input Format
        guard let inputFormat = AVAudioFormat(streamDescription: asbd) else { return }
        
        // 2. Define Target Format (48kHz, Float32, Mono)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000.0, channels: 1, interleaved: false) else { return }
        
        // 3. Setup Converter if needed
        if inputConverter == nil || inputConverter?.inputFormat != inputFormat {
            inputConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
            
            // Create Buffers
            let maxInputFrames = AVAudioFrameCount(4096)
            inputPCMBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: maxInputFrames)
            
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let maxOutputFrames = AVAudioFrameCount(Double(maxInputFrames) * ratio + 5)
            inputBuffer48k = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: maxOutputFrames)
        }
        
        guard let converter = inputConverter,
              let inputBuffer = inputPCMBuffer,
              let outputBuffer = inputBuffer48k else { return }
        
        // 4. Copy Data
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        inputBuffer.frameLength = AVAudioFrameCount(numSamples)
        
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(numSamples),
            into: inputBuffer.mutableAudioBufferList
        )
        
        guard status == noErr else {
            return
        }
        
        // 5. Convert
        var error: NSError? = nil
        
        var haveFed = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if !haveFed {
                outStatus.pointee = .haveData
                haveFed = true
                return inputBuffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        
        outputBuffer.frameLength = outputBuffer.frameCapacity
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        // 6. Write to Ring Buffer and Update Metering
        let convertedFrames = Int(outputBuffer.frameLength)
        
        if convertedFrames > 0, let floatData = outputBuffer.floatChannelData?[0] {
            // Metering (RMS)
            var sum: Float = 0
            for i in stride(from: 0, to: min(convertedFrames, 256), by: 4) {
                sum += floatData[i] * floatData[i]
            }
            if convertedFrames > 0 {
                let rms = sqrt(sum / Float(min(convertedFrames, 256)/4 + 1))
                DispatchQueue.main.async { self.inputLevel = rms }
            }
            
            // Push to RingBuffer
            _ = self.ringBuffer.write(floatData, count: convertedFrames)
        }
    }
    
    func shutdown() {
        captureSession.stopRunning()
        engine.stop()
    }
    
    deinit {
        shutdown()
    }
}
