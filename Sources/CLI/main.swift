import Foundation
import Core

print("MetalVoice CLI 🎙️")

// Basic Arg Parsing
var inputName: String?
var outputName: String?
var gain: Float = 1.0
var pipelineName: String?

var args = CommandLine.arguments
var i = 1
while i < args.count {
    switch args[i] {
    case "--in":
        if i + 1 < args.count { inputName = args[i + 1]; i += 1 }
    case "--out":
        if i + 1 < args.count { outputName = args[i + 1]; i += 1 }
    case "--gain":
        if i + 1 < args.count, let g = Float(args[i + 1]) { gain = g; i += 1 }
    case "--name":
        if i + 1 < args.count { pipelineName = args[i + 1]; i += 1 }
    case "--help":
        print("""
        MetalVoice CLI - AI-Powered Noise Suppression for macOS
        
        Usage: MetalVoiceCLI [OPTIONS]
        
        Options:
          --in <device>      Input device name (required)
          --out <device>     Output device name (required)
          --gain <float>     Output gain multiplier (default: 1.0, range: 0.5-4.0)
          --name <string>    Pipeline name for reference (default: "Pipeline")
          --help             Show this help message
        
        Examples:
          # Filter your microphone to a virtual cable
          ./MetalVoiceCLI --in "Built-in Microphone" --out "BlackHole 2ch"
          
          # Filter with custom gain
          ./MetalVoiceCLI --in "USB Microphone" --out "BlackHole 2ch" --gain 1.5
          
          # Run multiple pipelines (in separate terminals for dual filtering)
          Terminal 1: ./MetalVoiceCLI --in "Built-in Microphone" --out "BlackHole 2ch" --name "Microphone"
          Terminal 2: ./MetalVoiceCLI --in "Loopback Audio" --out "MacBook Pro Speakers" --name "Meeting"
        """)
        exit(0)
    default:
        break
    }
    i += 1
}

guard let input = inputName, let output = outputName else {
    print("Error: Missing required arguments --in or --out.")
    print("Use --help for usage information.")
    exit(1)
}

let pipeline = AudioPipeline(name: pipelineName ?? "Pipeline")

// Wait for device enumeration
RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))

// Note: AudioPipeline doesn't have direct device lists, so we'll try to set by name
// This works through the pipeline's device matching in the capture/playback setup

// For now, we'll need to enumerate through AudioModel to find the devices
let model = AudioModel()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

print("Available Input Devices: \(model.inputDevices.map { $0.localizedName })")
if let inDev = model.inputDevices.first(where: { $0.localizedName.localizedCaseInsensitiveContains(input) }) {
    print("✓ Selected Input: \(inDev.localizedName)")
    pipeline.selectedInputDeviceID = inDev.uniqueID
} else {
    print("✗ Error: Input device '\(input)' not found.")
    exit(1)
}

print("Available Output Devices: \(model.outputDevices.map { $0.name })")
if let outDev = model.outputDevices.first(where: { $0.name.localizedCaseInsensitiveContains(output) }) {
    print("✓ Selected Output: \(outDev.name)")
    pipeline.selectedOutputDeviceID = outDev.id
} else {
    print("✗ Error: Output device '\(output)' not found.")
    exit(1)
}

pipeline.outputGainValue = gain
pipeline.isEnabled = true

print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("🎙️  MetalVoice Pipeline: \(pipeline.name)")
print("┌─ Input:  \(model.inputDevices.first(where: { $0.uniqueID == pipeline.selectedInputDeviceID })?.localizedName ?? "Unknown")")
print("└─ Output: \(model.outputDevices.first(where: { $0.id == pipeline.selectedOutputDeviceID })?.name ?? "Unknown")")
print("   Gain:   \(Int(gain * 100))%")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("✓ AI Pipeline Active. Press Ctrl+C to stop.")
print()

// Keep alive
RunLoop.main.run()

