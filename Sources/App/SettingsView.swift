import SwiftUI
import Core

struct SettingsView: View {
    @ObservedObject var audioModel: AudioModel
    
    var body: some View {
        TabView {
            GeneralSettingsView(audioModel: audioModel)
                .tabItem {
                    Label("General", systemImage: "slider.horizontal.3")
                }
            
            PipelinesView(audioModel: audioModel)
                .tabItem {
                    Label("Pipelines", systemImage: "line.3.horizontal")
                }
            
            GuideView()
                .tabItem {
                    Label("Setup Guide", systemImage: "book.pages")
                }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 350)
    }
}

// MARK: - General Tab
struct GeneralSettingsView: View {
    @ObservedObject var audioModel: AudioModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Header
            HStack {
                Text("Audio Configuration")
                    .font(.headline)
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Gain Control Section
            if let pipeline = audioModel.selectedPipeline {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Output Gain", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("\(Int(pipeline.outputGainValue * 100))%")
                            .font(.monospacedDigit(.body)())
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.gray)
                            .font(.caption)
                        
                        Slider(value: $audioModel.outputGainValue, in: 0.5...4.0)
                            .tint(.accentColor)
                        
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    
                    Text("Boost the volume if the noise suppression makes your voice too quiet.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Spacer()
                        Button("Reset to 100%") {
                            withAnimation {
                                audioModel.outputGainValue = 1.0
                            }
                        }
                        .controlSize(.small)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                )
            }
            
            Spacer()
            
            // Footer / About
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("MetalVoice v1.1.1-b • Built with DeepFilterNet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
    }
}

// MARK: - Pipelines Tab
struct PipelinesView: View {
    @ObservedObject var audioModel: AudioModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Audio Pipelines")
                    .font(.headline)
                Spacer()
                
                if audioModel.pipelines.count < 2 {
                    Button(action: {
                        audioModel.addPipeline(name: "Received Audio")
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Add a second pipeline for filtering received audio")
                }
            }
            .padding(.bottom, 4)
            
            VStack(spacing: 12) {
                ForEach(audioModel.pipelines, id: \.id) { pipeline in
                    PipelineRow(
                        pipeline: pipeline,
                        audioModel: audioModel,
                        isSelected: pipeline.id == audioModel.selectedPipelineID,
                        onSelect: {
                            audioModel.selectPipeline(id: pipeline.id)
                        },
                        onDelete: {
                            if audioModel.pipelines.count > 1 {
                                audioModel.removePipeline(id: pipeline.id)
                            }
                        }
                    )
                }
            }
            
            Spacer()
            
            Text("You can configure up to 2 independent audio pipelines. Each pipeline can filter a different input/output combination.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct PipelineRow: View {
    @ObservedObject var pipeline: AudioPipeline
    @ObservedObject var audioModel: AudioModel
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pipeline.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    let inputName = audioModel.inputDevices.first(where: { $0.uniqueID == pipeline.selectedInputDeviceID })?.localizedName ?? "Unknown"
                    let outputName = audioModel.outputDevices.first(where: { $0.id == pipeline.selectedOutputDeviceID })?.name ?? "Unknown"
                    
                    Text("\(inputName) → \(outputName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(spacing: 8) {
                    Toggle("", isOn: $pipeline.isEnabled)
                        .toggleStyle(.switch)
                    
                    if audioModel.pipelines.count > 1 {
                        Button(action: onDelete) {
                            Image(systemName: "trash.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            if isSelected {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Input Device", systemImage: "mic.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $pipeline.selectedInputDeviceID) {
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
                        Picker("", selection: $pipeline.selectedOutputDeviceID) {
                            ForEach(audioModel.outputDevices) { device in
                                Text(device.name).tag(device.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Guide Tab
struct GuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Setup")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                StepRow(number: 1, title: "Input: Your Microphone", description: "Select your real physical microphone (e.g. Built-in, USB Mic) as the Input Device.")
                
                Divider()
                
                StepRow(number: 2, title: "Output: Virtual Cable", description: "Select 'BlackHole 2ch' (Recommended) as the Output Device.\nThis sends the enhanced audio to the virtual cable.")
                
                Divider()
                
                StepRow(number: 3, title: "Chat App Setup", description: "In Discord, Zoom, or OBS, set the Input Device to the same virtual cable (e.g. 'BlackHole 2ch').")
                
                Divider()
                
                StepRow(number: 4, title: "Enable AI", description: "Toggle 'DeepFilterNet AI' ON in the menu bar. Your voice is now processed!")
                
                HStack {
                    Spacer()
                    Label("Tip: You can use any virtual audio driver (like VB-Cable), but BlackHole is recommended.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.trailing)
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
