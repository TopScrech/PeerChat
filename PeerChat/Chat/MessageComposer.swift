import ScrechKit
import AVFoundation
import UniformTypeIdentifiers

struct MessageComposer: View {
    @Environment(Model.self) private var model
    
    private let person: Person
    private let proxy: ScrollViewProxy
    
    @State private var message = ""
    @State private var isShowingFilePicker = false
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    @State private var recordingStartedAt: Date?
    @State private var showError = false
    @State private var errorMessage = ""
    
    init(person: Person, proxy: ScrollViewProxy) {
        self.person = person
        self.proxy = proxy
    }
    
    var body: some View {
        HStack {
#if !os(tvOS)
            Button("Attach", systemImage: "paperclip", action: onPickFile)
                .labelStyle(.iconOnly)
                .title2()
                .secondary()
#endif
            
            TextField("Enter a message", text: $message)
                .onSubmit(onSend)
#if !os(tvOS)
                .textFieldStyle(.roundedBorder)
#endif
                .animation(.spring, value: message)
            
            Button(isRecording ? "Stop Recording" : "Record Voice", systemImage: isRecording ? "stop.circle.fill" : "mic.circle.fill", action: onRecordTapped)
                .labelStyle(.iconOnly)
                .title2()
                .foregroundStyle(isRecording ? .red : .secondary)
            
            if !message.isEmpty {
                Button("Send", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .title(.bold)
                    .foregroundStyle(.blue)
                    .animation(.spring, value: message)
            }
        }
        .padding()
#if !os(tvOS)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
#endif
        .alert("Could Not Send", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func onSend() {
        guard !message.isEmpty else { return }
        
        guard let chat = model.chats.first(where: { $0.person.id == person.id })?.chat else { return }
        
        model.send(message, chat: chat)
        message = ""
        scrollToLastMessage()
    }
    
    private func onPickFile() {
        isShowingFilePicker = true
    }
    
    private func onRecordTapped() {
        if isRecording {
            stopRecordingAndSend()
            return
        }
        
        Task {
            await startRecording()
        }
    }
    
    private func startRecording() async {
        let hasPermission = await requestMicrophoneAccess()
        
        guard hasPermission else {
            presentError("Microphone access is required to send voice messages")
            return
        }
        
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            #endif
            
            let url = FileManager.default
                .temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Int] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            
            audioRecorder = recorder
            recordingURL = url
            recordingStartedAt = Date()
            isRecording = true
        } catch {
            presentError("Could not start recording")
        }
    }
    
    private func stopRecordingAndSend() {
        guard let recorder = audioRecorder, let url = recordingURL else {
            cleanupRecording()
            return
        }
        
        recorder.stop()
        isRecording = false
        
        defer {
            try? FileManager.default.removeItem(at: url)
            cleanupRecording()
        }
        
        guard let chat = model.chats.first(where: { $0.person.id == person.id })?.chat else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            
            guard !data.isEmpty else {
                presentError("Voice message is empty")
                return
            }
            
            guard data.count <= model.maxAttachmentBytes else {
                presentError("Voice message is too large")
                return
            }
            
            let duration = max(Date().timeIntervalSince(recordingStartedAt ?? Date()), 0)
            
            model.sendVoiceMessage(
                data,
                duration: duration,
                chat: chat
            )
            
            scrollToLastMessage()
        } catch {
            presentError("Could not process recording")
        }
    }
    
    private func cleanupRecording() {
        audioRecorder = nil
        recordingURL = nil
        recordingStartedAt = nil
    }
    
    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            #if os(macOS)
            AVCaptureDevice.requestAccess(for: .audio) {
                continuation.resume(returning: $0)
            }
            #else
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
            #endif
        }
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            sendFile(url)
        case .failure:
            presentError("Could not load selected file")
        }
    }
    
    private func sendFile(_ url: URL) {
        guard let chat = model.chats.first(where: { $0.person.id == person.id })?.chat else { return }
        
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            let values = try url.resourceValues(forKeys: [.contentTypeKey, .nameKey, .fileSizeKey])
            let data = try Data(contentsOf: url)
            
            guard data.count <= model.maxAttachmentBytes else {
                presentError("Files larger than 10 MB are not supported")
                return
            }
            
            model.sendFile(
                data,
                fileName: values.name ?? url.lastPathComponent,
                fileType: values.contentType?.preferredMIMEType,
                chat: chat
            )
            
            scrollToLastMessage()
        } catch {
            presentError("Could not read selected file")
        }
    }
    
    private func scrollToLastMessage() {
        guard let last = model.chats.first(where: { $0.person.id == person.id })?.chat.messages.last else {
            return
        }
        
        withAnimation(.spring) {
            proxy.scrollTo(last.id)
        }
    }
    
    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
