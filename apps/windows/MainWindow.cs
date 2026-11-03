using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Media.SpeechSynthesis;
using Windows.Storage;

namespace MJCall;
public sealed class Clip { public string File { get; set; } = ""; public bool Interrupted { get; set; } }
public sealed class Inquiry {
    public string Id { get; set; } = Guid.NewGuid().ToString();
    public string Organization { get; set; } = "";
    public string Phone { get; set; } = "";
    public string Purpose { get; set; } = "";
    public string Questions { get; set; } = "";
    public string Notes { get; set; } = "";
    public string Outcome { get; set; } = "미확인";
    public List<Clip> Recordings { get; set; } = new();
}
public sealed class MainWindow : Window {
    private readonly StackPanel panel = new() { Margin = new Thickness(24), MaxWidth = 760 };
    private readonly TextBox organization, phone, purpose, questions, text, notes, outcome;
    private readonly CheckBox ready = new() { Content = "별도 전화기에서 발신하고 스피커폰을 켰어요", Margin = new Thickness(0, 10, 0, 10) };
    private readonly CheckBox consent = new() { Content = "상대에게 녹음을 안내하고 허락을 확인했어요", Margin = new Thickness(0, 10, 0, 10) };
    private readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap };
    private readonly StackPanel history = new(), clips = new();
    private readonly Button recordButton;
    private readonly string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "mj_call");
    private List<Inquiry> records = new();
    private Inquiry draft = new();
    private bool loadFailed, recordingBusy, recording;
    private MediaCapture? capture;
    private MediaPlayer? player;
    private SpeechSynthesisStream? speechStream;
    private Clip? pending;
    private int speechGeneration;
    public MainWindow() {
        Title = "mj_call"; Width = 900; Height = 900; MinWidth = 360; MinHeight = 500;
        Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Label("기관·고객센터 통화 도우미"); Label("수동 보조 단계입니다. 실제 발신·종료는 별도 전화기에서 합니다. AI 자동 응답은 아직 제공하지 않습니다.");
        organization = Field("전화할 곳"); phone = Field("전화번호"); purpose = Field("문의 목적"); questions = Field("질문 · 한 줄에 하나", 90);
        Button("문의 준비 저장", () => Save()); panel.Children.Add(ready);
        text = Field("대신 말할 내용", 90);
        Button("입력한 글 말하기", async () => { if (ready.IsChecked == true) await Speak(text.Text); else Message("전화기 준비를 확인해 주세요."); });
        Button("준비한 질문 말하기", async () => { if (ready.IsChecked == true) await Speak(questions.Text); });
        Button("잠시 기다려 달라고 말하기", async () => { if (ready.IsChecked == true) await Speak("잠시만 기다려 주세요. 답변을 준비하고 있습니다."); });
        Button("즉시 말하기 중지", StopPlayback);
        Label("녹음은 이 기기의 마이크 소리입니다. 전화 회선 원본이 아니며 주변 소음이 섞일 수 있습니다.");
        Button("녹음 허락 요청 말하기", async () => { if (ready.IsChecked == true) await Speak("통화 내용을 확인하기 위해 녹음해도 괜찮을까요?"); });
        panel.Children.Add(consent); panel.Children.Add(status);
        recordButton = Button("녹음 시작", async () => { if (recording) await StopRecording(false); else await StartRecording(); });
        outcome = Field("문의 결과"); notes = Field("답변·서류·기한·접수번호 메모", 110);
        Button("결과·메모 저장", () => Save()); Label("실제 전화는 전화기에서 종료해 주세요.");
        panel.Children.Add(clips); Button("듣기 중지", StopPlayback);
        Button("새 문의", () => { if (!recording && !recordingBusy) { StopPlayback(); LoadDraft(new()); } });
        Button("현재 문의와 녹음 삭제", Delete);
        Label("저장한 문의·통화 기록"); panel.Children.Add(history);
        try { Directory.CreateDirectory(root); var file = Path.Combine(root, "records.json"); if (System.IO.File.Exists(file)) records = JsonSerializer.Deserialize<List<Inquiry>>(System.IO.File.ReadAllText(file)) ?? new(); }
        catch { loadFailed = true; Message("기록을 읽지 못했습니다. 기존 파일은 덮어쓰지 않습니다."); }
        RefreshHistory();
        Closing += async (_, e) => {
            if (!recording && !recordingBusy) { StopPlayback(); if (!string.IsNullOrWhiteSpace(organization.Text)) Save(); return; }
            e.Cancel = true;
            if (recordingBusy) { Message("녹음 처리가 끝나면 다시 닫아 주세요."); return; }
            await StopRecording(true); Save(); Close();
        };
    }
    private void Label(string value) => panel.Children.Add(new TextBlock { Text = value, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 8), FontSize = 17 });
    private TextBox Field(string name, int height = 36) { Label(name); var box = new TextBox { MinHeight = height, AcceptsReturn = height > 36, TextWrapping = TextWrapping.Wrap, FontSize = 17 }; panel.Children.Add(box); return box; }
    private Button Button(string value, Action action) { var button = new Button { Content = value, MinHeight = 48, Margin = new Thickness(0, 5, 0, 5), Padding = new Thickness(8) }; button.Click += (_, _) => action(); panel.Children.Add(button); return button; }
    private void Message(string value) => status.Text = value;
    private void StopPlayback() { speechGeneration++; player?.Dispose(); player = null; speechStream?.Dispose(); speechStream = null; }
    private async Task Speak(string value) {
        if (string.IsNullOrWhiteSpace(value)) return;
        StopPlayback(); var generation = speechGeneration;
        try {
            using var synth = new SpeechSynthesizer();
            var voice = SpeechSynthesizer.AllVoices.FirstOrDefault(v => v.Language.Equals("ko-KR", StringComparison.OrdinalIgnoreCase));
            if (voice is null) { Message("Windows 설정에서 한국어 음성 팩을 설치해 주세요."); return; }
            synth.Voice = voice;
            var stream = await synth.SynthesizeTextToStreamAsync(value);
            if (generation != speechGeneration) { stream.Dispose(); return; }
            speechStream = stream; player = new MediaPlayer(); player.Source = MediaSource.CreateFromStream(stream, stream.ContentType); player.Play();
        } catch { Message("음성을 출력하지 못했어요."); }
    }
    private void ReadDraft() { draft.Organization = organization.Text; draft.Phone = phone.Text; draft.Purpose = purpose.Text; draft.Questions = questions.Text; draft.Notes = notes.Text; draft.Outcome = outcome.Text; }
    private bool Save() {
        if (loadFailed) { Message("기존 기록 읽기 오류가 있어 저장하지 않습니다."); return false; }
        ReadDraft(); if (string.IsNullOrWhiteSpace(draft.Organization) || string.IsNullOrWhiteSpace(draft.Purpose)) { Message("전화할 곳과 목적을 입력해 주세요."); return false; }
        var next = records.Where(r => r.Id != draft.Id).ToList(); next.Insert(0, draft);
        try { Write(next); records = next; RefreshHistory(); Message("저장했어요."); return true; }
        catch { Message("저장에 실패했어요. 화면을 유지하고 다시 저장해 주세요."); return false; }
    }
    private void Write(List<Inquiry> data) { var tmp = Path.Combine(root, "records.tmp"); System.IO.File.WriteAllText(tmp, JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true })); System.IO.File.Move(tmp, Path.Combine(root, "records.json"), true); }
    private async Task StartRecording() {
        if (recordingBusy || recording || ready.IsChecked != true || consent.IsChecked != true) { Message("전화기 준비와 녹음 허락을 확인해 주세요."); return; }
        if (!Save()) return;
        recordingBusy = true;
        try {
            StopPlayback(); capture = new MediaCapture();
            await capture.InitializeAsync(new MediaCaptureInitializationSettings { StreamingCaptureMode = StreamingCaptureMode.Audio });
            var folder = await StorageFolder.GetFolderFromPathAsync(root);
            var file = await folder.CreateFileAsync($"call_{Guid.NewGuid()}.m4a", CreationCollisionOption.FailIfExists);
            pending = new Clip { File = file.Name };
            await capture.StartRecordToStorageFileAsync(MediaEncodingProfile.CreateM4a(AudioEncodingQuality.Auto), file);
            recording = true; consent.IsEnabled = false; recordButton.Content = "녹음 중지·저장"; Message("● 녹음 중 — 앱을 열어 두세요");
        } catch { capture?.Dispose(); capture = null; pending = null; Message("녹음 시작에 실패했어요. Windows 마이크 개인정보 설정을 확인해 주세요."); }
        finally { recordingBusy = false; }
    }
    private async Task StopRecording(bool interrupted) {
        if (!recording || recordingBusy) return; recordingBusy = true;
        try { await capture!.StopRecordAsync(); if (pending != null) { pending.Interrupted = interrupted; draft.Recordings.Add(pending); Save(); } }
        catch { Message("녹음 종료에 실패했어요. 마지막 구간이 누락될 수 있어요."); }
        finally { capture?.Dispose(); capture = null; pending = null; recording = false; recordingBusy = false; consent.IsEnabled = true; recordButton.Content = "녹음 시작"; RefreshClips(); }
    }
    private void LoadDraft(Inquiry value) { draft = value; organization.Text = value.Organization; phone.Text = value.Phone; purpose.Text = value.Purpose; questions.Text = value.Questions; notes.Text = value.Notes; outcome.Text = value.Outcome; ready.IsChecked = false; consent.IsChecked = false; RefreshClips(); }
    private void RefreshHistory() { history.Children.Clear(); foreach (var record in records) { var b = new Button { Content = $"{record.Organization} · {record.Purpose}", MinHeight = 48 }; b.Click += (_, _) => { if (!recording && !recordingBusy) { StopPlayback(); LoadDraft(record); } }; history.Children.Add(b); } }
    private void RefreshClips() { clips.Children.Clear(); foreach (var clip in draft.Recordings) { var b = new Button { Content = $"녹음 듣기{(clip.Interrupted ? " · 중단됨" : "")}", MinHeight = 48 }; b.Click += async (_, _) => {
        if (recording || recordingBusy || Path.GetFileName(clip.File) != clip.File || !clip.File.StartsWith("call_")) return;
        try { StopPlayback(); var file = await StorageFile.GetFileFromPathAsync(Path.Combine(root, clip.File)); player = new MediaPlayer(); player.Source = MediaSource.CreateFromStorageFile(file); player.Play(); } catch { Message("녹음을 재생하지 못했어요."); }
    }; clips.Children.Add(b); } }
    private void Delete() {
        if (recording || recordingBusy || loadFailed || MessageBox.Show("현재 문의와 연결된 녹음을 삭제할까요?", "mj_call", MessageBoxButton.YesNo) != MessageBoxResult.Yes) return;
        try { StopPlayback(); foreach (var clip in draft.Recordings) { if (Path.GetFileName(clip.File) != clip.File || !clip.File.StartsWith("call_")) throw new IOException(); System.IO.File.Delete(Path.Combine(root, clip.File)); } var next = records.Where(r => r.Id != draft.Id).ToList(); Write(next); records = next; LoadDraft(new()); RefreshHistory(); }
        catch { Message("삭제하지 못했어요. 다시 시도해 주세요."); }
    }
}
