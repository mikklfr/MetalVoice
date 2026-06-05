import Foundation
import AVFoundation
import AVFAudio
import Combine
import AudioToolbox
import CoreAudio
import Accelerate

public class AudioModel: NSObject, ObservableObject {
    // Published State for UI
    @Published public var isAIEnabled: Bool = false {
        didSet {
            // Update all pipelines with the same state
            for pipeline in pipelines {
                pipeline.isEnabled = isAIEnabled
            }
        }
    }
    
    @Published public var pipelines: [AudioPipeline] = []
    @Published public var selectedPipelineID: UUID?
    
    @Published public var inputDevices: [AVCaptureDevice] = []
    @Published public var selectedInputDeviceID: String = "" {
        didSet {
            if let pipeline = selectedPipeline {
                pipeline.selectedInputDeviceID = selectedInputDeviceID
            }
        }
    }
    @Published public var errorMessage: String?
    @Published public var inputLevel: Float = 0.0
    @Published public var activeOutputDeviceName: String = "Unknown"
    @Published public var permissionStatus: String = "Unknown"
    
    // Output Selection
    @Published public var outputDevices: [DeviceStruct] = []
    @Published public var selectedOutputDeviceID: AudioObjectID = 0 {
        didSet {
            if let pipeline = selectedPipeline {
                pipeline.selectedOutputDeviceID = selectedOutputDeviceID
            }
        }
    }
    
    @Published public var isPlayingTestTone: Bool = false {
        didSet {
            for pipeline in pipelines {
                pipeline.isPlayingTestTone = isPlayingTestTone
            }
        }
    }
    
    @Published public var outputGainValue: Float = 1.0 {
        didSet {
            if let pipeline = selectedPipeline {
                pipeline.outputGainValue = outputGainValue
            }
        }
    }

    public struct DeviceStruct: Identifiable {
        public let id: AudioObjectID
        public let name: String
    }
    
    var selectedPipeline: AudioPipeline? {
        if let id = selectedPipelineID {
            return pipelines.first(where: { $0.id == id })
        }
        return pipelines.first
    }
    
    public override init() {
        super.init()
        
        checkPermissions()
        fetchInputDevices()
        fetchOutputDevices()
        
        // Create first default pipeline
        let pipeline = AudioPipeline(name: "Microphone")
        pipelines.append(pipeline)
        selectedPipelineID = pipeline.id
        
        // Set default devices
        if let defaultDev = AVCaptureDevice.default(for: .audio) {
            pipeline.selectedInputDeviceID = defaultDev.uniqueID
        } else if let first = inputDevices.first {
            pipeline.selectedInputDeviceID = first.uniqueID
        }
        
        if let bh = outputDevices.first(where: { $0.name.contains("BlackHole") }) {
            pipeline.selectedOutputDeviceID = bh.id
        } else if let first = outputDevices.first {
            pipeline.selectedOutputDeviceID = first.id
        }
    }
    
    func fetchOutputDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        let deviceCount = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var deviceIDs = [AudioObjectID](repeating: 0, count: deviceCount)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        
        var newDevs: [DeviceStruct] = []
        
        for id in deviceIDs {
            // Check Output Channels
            let scope = kAudioObjectPropertyScopeOutput
            var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: 0)
            var size: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size)
            if size > 0 {
                var nameSize = UInt32(MemoryLayout<CFString?>.size)
                var namePtr: Unmanaged<CFString>?
                var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &namePtr)
                if let cf = namePtr?.takeRetainedValue() {
                   newDevs.append(DeviceStruct(id: id, name: cf as String))
                }
            }
        }
        
        DispatchQueue.main.async {
            self.outputDevices = newDevs
        }
    }
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permissionStatus = "Authorized"
        case .denied: permissionStatus = "Denied"
        case .restricted: permissionStatus = "Restricted"
        case .notDetermined:
            permissionStatus = "Not Determined"
            AVCaptureDevice.requestAccess(for: .audio) { g in
                DispatchQueue.main.async { self.permissionStatus = g ? "Authorized" : "Denied" }
            }
        @unknown default: permissionStatus = "Unknown"
        }
    }
    
    func fetchInputDevices() {
        let types: [AVCaptureDevice.DeviceType] = [.builtInMicrophone, .externalUnknown]
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .audio, position: .unspecified)
        
        var devs = session.devices
        devs.sort { $0.localizedName < $1.localizedName }
        
        DispatchQueue.main.async {
            self.inputDevices = devs
        }
    }
    
    /// Add a new audio pipeline
    public func addPipeline(name: String = "Pipeline") {
        guard pipelines.count < 2 else {
            errorMessage = "Maximum 2 pipelines supported"
            return
        }
        
        let pipeline = AudioPipeline(name: name)
        
        // Use same output device as first pipeline if available
        if let first = pipelines.first {
            pipeline.selectedOutputDeviceID = first.selectedOutputDeviceID
        }
        
        pipelines.append(pipeline)
        selectedPipelineID = pipeline.id
        pipeline.isEnabled = isAIEnabled
    }
    
    /// Remove a pipeline by ID
    public func removePipeline(id: UUID) {
        pipelines.removeAll { $0.id == id }
        if selectedPipelineID == id {
            selectedPipelineID = pipelines.first?.id
        }
    }
    
    /// Select a pipeline
    public func selectPipeline(id: UUID) {
        guard pipelines.contains(where: { $0.id == id }) else { return }
        selectedPipelineID = id
    }
}
