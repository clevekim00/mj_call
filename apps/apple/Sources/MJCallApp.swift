import SwiftUI
import AVFoundation

struct Recording: Codable, Identifiable {
    var id = UUID().uuidString
    var file: String
    var startedAt = Date()
    var interrupted = false
}
struct Inquiry: Codable, Identifiable {
    var id = UUID().uuidString
    var organization = ""
    var phone = ""
    var purpose = ""
    var questions = "필요한 서류가 무엇인가요?\n신청 방법과 접수 기한을 알려 주세요."
    var notes = ""
    var outcome = "미확인"
    var recordings: [Recording] = []
}

@MainActor final class CallStore: ObservableObject {
    @Published var records: [Inquiry] = []
    @Published var error = ""
    let root: URL
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("mj_call", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let url = root.appendingPathComponent("records.json")
            if FileManager.default.fileExists(atPath: url.path) {
                records = try JSONDecoder().decode([Inquiry].self, from: Data(contentsOf: url))
            }
        } catch { self.error = "기록을 읽지 못했어요. 기존 파일은 덮어쓰지 않습니다."; loadFailed = true }
    }
    private var loadFailed = false
    func save(_ inquiry: Inquiry) {
        guard !loadFailed, !inquiry.organization.trimmingCharacters(in: .whitespaces).isEmpty, !inquiry.purpose.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let previous = records
        records.removeAll { $0.id == inquiry.id }; records.insert(inquiry, at: 0)
        do { try JSONEncoder().encode(records).write(to: root.appendingPathComponent("records.json"), options: .atomic); error = "" }
        catch { records = previous; self.error = "저장에 실패했어요. 화면을 유지하고 다시 저장해 주세요." }
    }
    func delete(_ inquiry: Inquiry) -> Bool {
        guard !loadFailed else { return false }
        do {
            for clip in inquiry.recordings {
                // Never unlink an imported or arbitrary filesystem path.
                guard clip.file == URL(fileURLWithPath: clip.file).lastPathComponent, clip.file.hasPrefix("call_") else { throw CocoaError(.fileReadInvalidFileName) }
                let url = root.appendingPathComponent(clip.file)
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            }
            let remaining = records.filter { $0.id != inquiry.id }
            try JSONEncoder().encode(remaining).write(to: root.appendingPathComponent("records.json"), options: .atomic)
            records = remaining; return true
        } catch { self.error = "삭제에 실패했어요. 다시 시도해 주세요."; return false }
    }
}

@MainActor final class CallAudio: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var recording = false
    @Published var error = ""
    private let speech = AVSpeechSynthesizer()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var pending: Recording?
    func speak(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let voice = AVSpeechSynthesisVoice(language: "ko-KR") else { error = "기기에 한국어 음성을 설치해 주세요."; return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            if session.category != .playAndRecord { try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker]) }
            try session.setActive(true)
            #endif
            speech.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: text); utterance.voice = voice; utterance.rate = 0.42
            speech.speak(utterance)
        } catch { self.error = "음성 출력에 실패했어요." }
    }
    func stopSpeech() { speech.stopSpeaking(at: .immediate) }
    func start(root: URL) async {
        guard !recording else { return }
        let granted: Bool
        #if os(iOS)
        granted = await withCheckedContinuation { continuation in AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) } }
        #else
        granted = await AVCaptureDevice.requestAccess(for: .audio)
        #endif
        guard granted else { error = "시스템 설정에서 마이크 권한을 허용해 주세요."; return }
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker]); try session.setActive(true)
            #endif
            player?.stop()
            let clip = Recording(file: "call_\(UUID().uuidString).m4a")
            let next = try AVAudioRecorder(url: root.appendingPathComponent(clip.file), settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128000])
            guard next.prepareToRecord(), next.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = next; pending = clip; recording = true; error = ""
        } catch { self.error = "녹음을 시작하지 못했어요." }
    }
    func stop(interrupted: Bool = false) -> Recording? {
        recorder?.stop(); recorder = nil; recording = false
        guard var clip = pending else { return nil }; pending = nil; clip.interrupted = interrupted
        return clip
    }
    func play(_ url: URL) {
        guard !recording else { return }
        do { player?.stop(); player = try AVAudioPlayer(contentsOf: url); guard player!.play() else { throw CocoaError(.fileReadCorruptFile) } }
        catch { self.error = "녹음을 재생하지 못했어요." }
    }
    func stopPlayback() { player?.stop() }
}

struct CallView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var store = CallStore()
    @StateObject private var audio = CallAudio()
    @State private var draft = Inquiry()
    @State private var text = ""
    @State private var ready = false
    @State private var consent = false
    @State private var starting = false
    @State private var deleteRequested = false
    private func stopRecording(interrupted: Bool = false) {
        if let clip = audio.stop(interrupted: interrupted) { draft.recordings.append(clip); store.save(draft) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("기관·고객센터 통화 도우미").font(.title2.bold())
                    Text("별도 전화기로 발신하고 스피커폰을 켜 주세요. 현재는 수동 보조이며 AI 자동 응답은 제공하지 않아요.")
                    TextField("전화할 곳", text: $draft.organization).disabled(audio.recording || starting)
                    TextField("전화번호 (자동 발신하지 않음)", text: $draft.phone)
                    TextField("문의 목적", text: $draft.purpose)
                    Text("질문 · 한 줄에 하나")
                    TextEditor(text: $draft.questions).frame(minHeight: 90)
                    Button("문의 준비 저장") { store.save(draft) }.disabled(draft.organization.isEmpty || draft.purpose.isEmpty)
                    Toggle("별도 전화기의 스피커폰을 켰어요", isOn: $ready)
                    TextField("대신 말할 내용", text: $text, axis: .vertical).lineLimit(2...5)
                    Button("입력한 글 말하기") { audio.speak(text) }.disabled(!ready || starting)
                    Button("즉시 말하기 중지", role: .destructive) { audio.stopSpeech() }
                    ForEach(Array(draft.questions.split(separator: "\n").map(String.init).enumerated()), id: \.offset) { _, phrase in
                        Button(phrase) { audio.speak(phrase) }.disabled(!ready)
                    }
                    Button("잠시 기다려 달라고 말하기") { audio.speak("잠시만 기다려 주세요. 답변을 준비하고 있습니다.") }.disabled(!ready)
                    Divider()
                    Text("마이크 녹음 · 전화 회선 원본 녹음이 아니며 주변 소리가 섞일 수 있어요.")
                    Button("녹음 허락 요청 말하기") { audio.speak("통화 내용을 확인하기 위해 녹음해도 괜찮을까요?") }.disabled(!ready)
                    Toggle("상대에게 녹음을 안내하고 허락을 확인했어요", isOn: $consent).disabled(audio.recording || starting)
                    Button(audio.recording ? "녹음 중지·저장" : "녹음 시작") {
                        if audio.recording { stopRecording() }
                        else { starting = true; Task { await audio.start(root: store.root); starting = false; if phase != .active { stopRecording(interrupted: true) } } }
                    }.disabled(starting || (!audio.recording && (!ready || !consent || draft.organization.isEmpty || draft.purpose.isEmpty)))
                    Text(audio.recording ? "● 녹음 중 — 이 화면을 열어 두세요" : "녹음 꺼짐")
                    Picker("문의 결과", selection: $draft.outcome) {
                        ForEach(["미확인", "답변 확인", "일부 답변", "접수·회신 대기", "본인 인증 필요", "연결 실패"], id: \.self) { Text($0) }
                    }
                    TextEditor(text: $draft.notes).frame(minHeight: 100).accessibilityLabel("답변·기한·접수번호 메모")
                    Button("결과·메모 저장") { store.save(draft) }
                    Text("실제 통화는 전화기에서 종료해 주세요.")
                    ForEach(draft.recordings) { clip in
                        Button("녹음 듣기 · \(clip.startedAt.formatted())\(clip.interrupted ? " · 중단됨" : "")") { audio.play(store.root.appendingPathComponent(clip.file)) }.disabled(audio.recording)
                    }
                    Button("듣기 중지") { audio.stopPlayback() }
                    if !audio.error.isEmpty { Text(audio.error).foregroundStyle(.red) }
                    if !store.error.isEmpty { Text(store.error).foregroundStyle(.red) }
                    Divider()
                    Button("새 문의") { audio.stopSpeech(); audio.stopPlayback(); draft = Inquiry(); ready = false; consent = false }.disabled(audio.recording || starting)
                    Text("저장한 문의·통화 기록").font(.headline)
                    ForEach(store.records) { record in
                        Button("\(record.organization) · \(record.purpose)") { audio.stopSpeech(); audio.stopPlayback(); draft = record; ready = false; consent = false }.disabled(audio.recording || starting)
                    }
                    Button("현재 문의와 녹음 삭제", role: .destructive) { deleteRequested = true }.disabled(audio.recording || starting)
                }.textFieldStyle(.roundedBorder).buttonStyle(.bordered).padding().frame(maxWidth: 760)
            }.navigationTitle("mj_call")
            .confirmationDialog("현재 문의와 연결된 녹음을 삭제할까요?", isPresented: $deleteRequested) {
                Button("삭제", role: .destructive) { audio.stopPlayback(); if store.delete(draft) { draft = Inquiry() } }
            }
            .onChange(of: phase) { next in if next == .background { audio.stopSpeech(); stopRecording(interrupted: true); store.save(draft) } }
            .onDisappear { audio.stopSpeech(); audio.stopPlayback(); stopRecording(interrupted: true) }
        }
    }
}
@main struct MJCallApp: App { var body: some Scene { WindowGroup { CallView() } } }
