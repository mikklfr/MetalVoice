import SwiftUI
import CoreAudio
import Core

struct ContentView: View {
    @ObservedObject var audioModel: AudioModel
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                if let path = Bundle.main.path(forResource: "MetalVoiceLogo", ofType: "png"),
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .cornerRadius(8)
                } else {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading) {
                    Text("MetalVoice")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("AI Audio Enhancer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // Settings Button
                Button(action: {
                    WindowManager.openSettings(model: audioModel)
                }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            
            Divider()
            
            // Status & Pipeline Section
            VStack(alignment: .leading, spacing: 12) {
                // Status with Live Indicator
                HStack {
                    Circle()
                        .fill(audioModel.isAIEnabled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(audioModel.isAIEnabled ? "AI Active" : "Passthrough")
                        .font(.caption)
                        .fontWeight(.medium)
                    Spacer()
                    // Meter - show selected pipeline's input level
                    if let pipeline = audioModel.selectedPipeline {
                        MeterView(level: pipeline.inputLevel, refreshTrigger: audioModel.refreshTrigger)
                            .frame(width: 100, height: 6)
                    } else {
                        MeterView(level: 0, refreshTrigger: audioModel.refreshTrigger)
                            .frame(width: 100, height: 6)
                    }
                }
                
                // Pipeline Selector
                if audioModel.pipelines.count > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Pipeline", systemImage: "line.3.horizontal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            if audioModel.pipelines.count < 2 {
                                Button(action: {
                                    audioModel.addPipeline(name: "Received Audio")
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.plain)
                                .help("Add a second pipeline")
                            }
                        }
                        Picker("", selection: $audioModel.selectedPipelineID) {
                            ForEach(audioModel.pipelines, id: \.id) { pipeline in
                                Text(pipeline.name).tag(Optional(pipeline.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            
            Divider()
            
            // Devices
            if audioModel.selectedPipeline != nil {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Input Device", systemImage: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: audioModel.selectedPipelineInputBinding) {
                            ForEach(audioModel.inputDevices, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Output Device", systemImage: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: audioModel.selectedPipelineOutputBinding) {
                            ForEach(audioModel.outputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            
            Divider()
            
            // Controls
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $audioModel.isAIEnabled) {
                    Text("DeepFilterNet AI")
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
                
                Spacer()
                
                if let error = audioModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .help(error)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct MeterView: View {
    var level: Float
    var refreshTrigger: UUID = UUID()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .opacity(0.2)
                    .foregroundColor(.gray)
                
                Capsule()
                    .frame(width: min(CGFloat(level) * 5 * geometry.size.width, geometry.size.width))
                    .foregroundColor(level > 0.01 ? .green : .gray)
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
        .id(refreshTrigger)
    }
}

class WindowManager {
    static var settingsWindow: NSWindow?
    
    static func openSettings(model: AudioModel) {
        if settingsWindow == nil {
            let view = SettingsView(audioModel: model)
            // Standard Window (Larger Buttons + Resizable)
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            panel.center()
            panel.title = "MetalVoice Settings"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.contentView = NSHostingView(rootView: view)
            panel.isFloatingPanel = false
            panel.isReleasedWhenClosed = false 
            panel.minSize = NSSize(width: 450, height: 350) 
            
            settingsWindow = panel
            
            // Cleanup on close
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: nil) { _ in
                settingsWindow = nil
            }
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
