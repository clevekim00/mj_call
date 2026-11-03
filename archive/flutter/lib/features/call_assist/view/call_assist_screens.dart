import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:speech_rehab/features/rehab/view/rehab_ui.dart';
import '../model/call_record.dart';
import '../services/call_audio.dart';
import '../services/call_controller.dart';
import '../services/call_repository.dart';

final callAudioFactoryProvider = Provider<CallAudio Function()>(
  (ref) => DeviceCallAudio.new,
);
String _tr(BuildContext c, String ko, String en) => rehabEnglish(c) ? en : ko;
String _date(DateTime value) =>
    '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _duration(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
const _outcomes = {
  'notReviewed': ('미확인', 'Not reviewed'),
  'answered': ('답변 확인', 'Answers received'),
  'partial': ('일부 답변', 'Partial answers'),
  'waiting': ('접수·회신 대기', 'Awaiting reply'),
  'authentication': ('본인 인증 필요', 'Authentication needed'),
  'failed': ('연결·문의 실패', 'Could not complete inquiry'),
};
String _outcome(BuildContext c, String key) {
  final label = _outcomes[key] ?? _outcomes['notReviewed']!;
  return rehabEnglish(c) ? label.$2 : label.$1;
}

class CallAssistHomeScreen extends ConsumerStatefulWidget {
  const CallAssistHomeScreen({super.key});
  @override
  ConsumerState<CallAssistHomeScreen> createState() => _CallHomeState();
}

class _CallHomeState extends ConsumerState<CallAssistHomeScreen> {
  late Future<List<CallRecord>> _records;
  void _reload() {
    _records = ref.read(callRepositoryProvider).load();
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => RehabPage(
    title: _tr(context, '통화 도우미', 'Call assistant'),
    children: [
      Text(
        _tr(context, '기관·고객센터 문의', 'Agency and customer service inquiries'),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      Text(
        _tr(
          context,
          '별도 전화기로 전화를 걸고 스피커폰을 켜 주세요. 이 기기는 입력한 글을 한국어로 읽고, 원할 때 마이크로 녹음해요.',
          'Call on a separate phone with speakerphone enabled. This device speaks your text in Korean and optionally records its microphone.',
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _tr(
          context,
          '현재는 직접 조작하는 통화 보조 기능이에요. 상대 말 자동 인식·AI 자동 응답은 제공하지 않아요.',
          'This version is manually controlled. Automatic transcription and AI replies are not included.',
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: () => _open(const CallPreparationScreen()),
        icon: const Icon(Icons.add_call),
        label: Text(_tr(context, '새 통화 준비', 'Prepare a call')),
      ),
      const SizedBox(height: 24),
      Text(
        _tr(context, '준비한 문의 · 최근 통화', 'Prepared inquiries and recent calls'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      FutureBuilder<List<CallRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Column(
              children: [
                Text(_tr(context, '기록을 불러오지 못했어요.', 'Could not load records.')),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: Text(_tr(context, '다시 시도', 'Retry')),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return Text(
              _tr(
                context,
                '준비한 문의가 없어요. 전화할 곳과 물어볼 내용을 먼저 적어 보세요.',
                'No inquiries yet. Start with whom to call and what to ask.',
              ),
            );
          }
          return Column(
            children: [
              for (final record in snapshot.data!)
                RehabCard(
                  title: record.organization,
                  subtitle:
                      '${record.purpose}\n${_date(record.createdAt)} · ${record.completed ? _outcome(context, record.outcome) : _tr(context, '준비·진행 중', 'Prepared / in progress')} · ${_tr(context, '녹음', 'Recordings')} ${record.recordings.length}',
                  icon: record.completed ? Icons.history : Icons.edit_note,
                  onTap: () => _open(CallRecordScreen(record: record)),
                ),
            ],
          );
        },
      ),
    ],
  );
}

class CallPreparationScreen extends ConsumerStatefulWidget {
  const CallPreparationScreen({super.key, this.source});
  final CallRecord? source;
  @override
  ConsumerState<CallPreparationScreen> createState() => _PreparationState();
}

class _PreparationState extends ConsumerState<CallPreparationScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _organization,
      _phone,
      _purpose,
      _questions,
      _allowed;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _organization = TextEditingController(text: widget.source?.organization);
    _phone = TextEditingController(text: widget.source?.phone);
    _purpose = TextEditingController(text: widget.source?.purpose);
    _questions = TextEditingController(text: widget.source?.questions);
    // Reusing a plan must not silently renew permission to disclose old details.
    _allowed = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [_organization, _phone, _purpose, _questions, _allowed]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool start) async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final record = CallRecord(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      organization: _organization.text.trim(),
      phone: _phone.text.trim(),
      purpose: _purpose.text.trim(),
      questions: _questions.text.trim(),
      allowedInfo: _allowed.text.trim(),
    );
    try {
      await ref.read(callRepositoryProvider).save(record);
      if (!mounted) return;
      if (start) {
        await Navigator.pushReplacement(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CallSessionScreen(record: record),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _tr(
            context,
            '준비 내용을 저장하지 못했어요. 다시 시도해 주세요.',
            'Could not save. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: RehabPage(
      title: _tr(context, '통화 준비', 'Prepare an inquiry'),
      children: [
        Text(
          _tr(
            context,
            '기관·고객센터에 물어볼 내용을 준비해요',
            'Prepare questions for an agency or customer service',
          ),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: Column(
            children: [
              _field(
                _organization,
                '전화할 곳',
                'Organization',
                required: true,
                maxLength: 100,
              ),
              _field(
                _phone,
                '전화번호 (선택)',
                'Phone number (optional)',
                phone: true,
                maxLength: 40,
              ),
              _field(
                _purpose,
                '문의 목적',
                'Purpose',
                required: true,
                lines: 2,
                maxLength: 500,
              ),
              _field(
                _questions,
                '꼭 확인할 질문 (한 줄에 하나)',
                'Questions (one per line)',
                lines: 4,
                maxLength: 2000,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final q in [
                    '필요한 서류가 무엇인가요?',
                    '어떤 방법으로 신청하나요?',
                    '접수 기한은 언제인가요?',
                    '담당 부서와 연락처를 알려 주세요.',
                  ])
                    ActionChip(
                      label: Text(q),
                      onPressed: _saving
                          ? null
                          : () {
                              _questions.text = [
                                _questions.text.trim(),
                                q,
                              ].where((s) => s.isNotEmpty).join('\n');
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _field(
                _allowed,
                '전달해도 되는 정보 (선택)',
                'Information you choose to share (optional)',
                lines: 2,
                maxLength: 1000,
              ),
            ],
          ),
        ),
        Text(
          _tr(
            context,
            '비밀번호·인증번호는 적지 마세요. 정보는 자동으로 읽지 않으며, 통화 중 선택한 문장만 읽어요. 준비 내용과 녹음은 이 기기에 저장하고 외부 AI로 전송하지 않아요.',
            'Do not enter passwords or verification codes. Information is never read automatically. Only selected text is spoken. This feature stores data on this device and does not send it to an AI service.',
          ),
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(true),
          icon: const Icon(Icons.phone_in_talk),
          label: Text(
            _tr(context, '저장하고 통화 보조 열기', 'Save and open call controls'),
          ),
        ),
        TextButton(
          onPressed: _saving ? null : () => _save(false),
          child: Text(_tr(context, '준비만 저장', 'Save for later')),
        ),
      ],
    ),
  );
  Widget _field(
    TextEditingController c,
    String ko,
    String en, {
    bool required = false,
    bool phone = false,
    int lines = 1,
    int maxLength = 500,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: !_saving,
      minLines: lines,
      maxLines: lines + 2,
      maxLength: maxLength,
      keyboardType: phone ? TextInputType.phone : TextInputType.multiline,
      decoration: InputDecoration(
        labelText: _tr(context, ko, en),
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
                ? _tr(context, '내용을 입력해 주세요.', 'Please enter a value.')
                : null
          : null,
    ),
  );
}

class CallSessionScreen extends ConsumerStatefulWidget {
  const CallSessionScreen({super.key, required this.record});
  final CallRecord record;
  @override
  ConsumerState<CallSessionScreen> createState() => _SessionState();
}

class _SessionState extends ConsumerState<CallSessionScreen>
    with WidgetsBindingObserver {
  late final CallController _controller;
  final _input = TextEditingController(), _notes = TextEditingController();
  bool _phoneReady = false, _recordingConsent = false, _leaving = false;
  late String _selectedOutcome;
  Future<void>? _suspending;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = CallController(
      record: widget.record,
      repository: ref.read(callRepositoryProvider),
      audio: ref.read(callAudioFactoryProvider)(),
    );
    _notes.text = widget.record.notes;
    _selectedOutcome = widget.record.outcome;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (_suspending != null) return;
      _controller.updateResult(_notes.text, _selectedOutcome);
      _suspending = _controller
          .interrupt()
          .then((_) async {
            await _controller.save();
          })
          .whenComplete(() => _suspending = null);
      unawaited(_suspending);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _input.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _leave({bool complete = false}) async {
    if (_leaving || _controller.recordingBusy || _controller.saving) return;
    _leaving = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          _tr(
            context,
            complete ? '전화기에서 통화를 종료했나요?' : '통화 보조를 나갈까요?',
            complete
                ? 'Have you ended the phone call?'
                : 'Leave call controls?',
          ),
        ),
        content: Text(
          _tr(
            context,
            '앱은 실제 전화를 끊지 않아요. 말하기와 녹음을 멈추고 기록을 저장해요.',
            'This app cannot hang up your phone. Speech and recording will stop, and your record will be saved.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_tr(c, '계속하기', 'Stay')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              _tr(
                c,
                complete ? '전화 종료 확인·저장' : '중단하고 저장',
                complete ? 'Phone ended · save' : 'Stop and save',
              ),
            ),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      _leaving = false;
      return;
    }
    await _controller.interrupt();
    _controller.updateResult(_notes.text, _selectedOutcome);
    final saved = await _controller.save(complete: complete);
    if (saved && mounted) {
      Navigator.pop(context);
    } else {
      _leaving = false;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) {
      final busy = _controller.recordingBusy || _controller.saving;
      final canSpeak = _phoneReady && !_controller.speaking && !busy;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_leave());
        },
        child: RehabPage(
          title: _tr(context, '통화 중 보조', 'Call controls'),
          actions: [
            IconButton(
              tooltip: _tr(context, '저장하고 나가기', 'Save and leave'),
              onPressed: busy ? null : () => _leave(),
              icon: const Icon(Icons.close),
            ),
          ],
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                key: const Key('call-stop-speech'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () => _controller.stopSpeaking(),
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(_tr(context, '즉시 말하기 중지', 'Stop speaking now')),
              ),
              Text(
                _tr(
                  context,
                  '실제 전화는 전화기에서 종료해 주세요.',
                  'End the actual call on your phone.',
                ),
              ),
            ],
          ),
          children: [
            Text(
              _controller.record.organization,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_controller.record.phone.isNotEmpty)
              SelectableText(_controller.record.phone),
            Text(_controller.record.purpose),
            OutlinedButton.icon(
              onPressed: !_phoneReady && !_controller.speaking && !busy
                  ? () => _controller.speak(
                      '통화 도우미 소리 점검입니다. 전화기를 옆에 놓고 스피커 소리를 확인해 주세요.',
                    )
                  : null,
              icon: const Icon(Icons.volume_up_outlined),
              label: Text(
                _tr(context, '전화 걸기 전 소리 점검', 'Test sound before calling'),
              ),
            ),
            CheckboxListTile(
              key: const Key('call-phone-ready'),
              contentPadding: EdgeInsets.zero,
              value: _phoneReady,
              onChanged: (value) => setState(() => _phoneReady = value == true),
              title: Text(
                _tr(
                  context,
                  '별도 전화기에서 발신하고 스피커폰을 켰어요',
                  'I called on a separate phone and enabled speakerphone',
                ),
              ),
            ),
            Text(
              _tr(
                context,
                _controller.speaking ? '한국어로 말하는 중' : '직접 입력·문장 선택 대기',
                _controller.speaking
                    ? 'Speaking in Korean'
                    : 'Ready for your text or a phrase',
              ),
              semanticsLabel: _controller.speaking ? '말하는 중' : null,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('call-text-input'),
              controller: _input,
              minLines: 2,
              maxLines: 5,
              maxLength: 1500,
              decoration: InputDecoration(
                labelText: _tr(
                  context,
                  '대신 말할 내용을 입력하세요',
                  'Type what you want to say in Korean',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            FilledButton.icon(
              key: const Key('call-speak-text'),
              onPressed: canSpeak ? () => _controller.speak(_input.text) : null,
              icon: const Icon(Icons.volume_up),
              label: Text(_tr(context, '입력한 글 말하기', 'Speak typed text')),
            ),
            const SizedBox(height: 16),
            Text(
              _tr(
                context,
                '준비 문장 · 누르면 바로 말해요',
                'Prepared phrases · tap to speak',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final phrase in {
              '안녕하세요. 음성 도우미로 대화하고 있습니다. 사용자가 옆에서 내용을 확인하고 있어요.',
              _controller.record.purpose,
              ..._controller.record.questions
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty),
              '잠시만 기다려 주세요. 답변을 준비하고 있습니다.',
              '잘 듣지 못했어요. 천천히 다시 말씀해 주세요.',
              '담당 부서로 연결해 주실 수 있나요?',
              '안내받은 내용을 다시 확인하고 싶습니다.',
              '감사합니다. 통화를 마치겠습니다.',
            })
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: canSpeak ? () => _controller.speak(phrase) : null,
                  child: Text(phrase),
                ),
              ),
            if (_controller.record.allowedInfo.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                _tr(
                  context,
                  '전달 허용 정보 · 읽으려면 입력창에 복사하세요',
                  'Information you allowed · copy to the text box to speak',
                ),
              ),
              SelectableText(_controller.record.allowedInfo),
            ],
            const Divider(height: 32),
            Text(
              _tr(context, '통화 녹음', 'Call recording'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              _tr(
                context,
                '이 기기의 마이크로 주변 소리를 녹음해요. 전화 회선 원본 녹음이 아니며 소음이 섞일 수 있어요. 이 화면을 열어 둬 주세요. 화면 잠금·다른 앱 이동 시 녹음을 멈추고 저장해요.',
                'Records this device’s microphone, not the phone line. Nearby noise may be included. Keep this screen open; locking or leaving the app stops and saves capture.',
              ),
            ),
            CheckboxListTile(
              key: const Key('call-record-consent'),
              contentPadding: EdgeInsets.zero,
              value: _recordingConsent,
              onChanged: _controller.recording || busy
                  ? null
                  : (value) =>
                        setState(() => _recordingConsent = value == true),
              title: Text(
                _tr(
                  context,
                  '상대에게 녹음을 안내하고 허락을 확인했어요',
                  'I informed the other person and confirmed permission to record',
                ),
              ),
            ),
            if (!_controller.recording)
              OutlinedButton(
                onPressed: canSpeak
                    ? () => _controller.speak('통화 내용을 확인하기 위해 녹음해도 괜찮을까요?')
                    : null,
                child: Text(
                  _tr(context, '녹음 허락 요청 말하기', 'Ask permission to record'),
                ),
              ),
            Semantics(
              liveRegion: true,
              child: Text(
                _controller.recording
                    ? '${_tr(context, '녹음 중', 'Recording')} · ${_duration(_controller.elapsedSeconds)}'
                    : _tr(context, '녹음 꺼짐', 'Recording off'),
              ),
            ),
            FilledButton.icon(
              key: const Key('call-record-toggle'),
              onPressed:
                  busy ||
                      (!_controller.recording &&
                          (!_phoneReady ||
                              !_recordingConsent ||
                              _controller.unsaved))
                  ? null
                  : () {
                      if (_controller.recording) {
                        unawaited(_controller.stopRecording());
                      } else {
                        unawaited(
                          _controller.startRecording(
                            consentConfirmed: _recordingConsent,
                          ),
                        );
                      }
                    },
              icon: Icon(_controller.recording ? Icons.stop : Icons.mic),
              label: Text(
                _tr(
                  context,
                  _controller.recording ? '녹음 중지·저장' : '녹음 시작',
                  _controller.recording
                      ? 'Stop and save recording'
                      : 'Start recording',
                ),
              ),
            ),
            Text(
              '${_tr(context, '기록에 연결된 녹음', 'Recordings attached')}: ${_controller.record.recordings.length}',
            ),
            if (_controller.error != null) _ErrorText(_controller.error!),
            if (_controller.record.recordingIncomplete)
              Text(
                _tr(
                  context,
                  '녹음 중단·누락이 있어요. 전체 통화가 녹음된 것은 아니에요.',
                  'Recording was interrupted or incomplete. The full call was not captured.',
                ),
              ),
            if (_controller.unsaved)
              TextButton(
                onPressed: busy ? null : () => _controller.save(),
                child: Text(_tr(context, '저장 다시 시도', 'Retry saving')),
              ),
            const Divider(height: 32),
            Text(
              _tr(context, '문의 결과 · 직접 기록', 'Inquiry result · your notes'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            DropdownButtonFormField<String>(
              initialValue: _selectedOutcome,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: _tr(context, '현재 결과', 'Current outcome'),
              ),
              items: [
                for (final key in _outcomes.keys)
                  DropdownMenuItem(
                    value: key,
                    child: Text(_outcome(context, key)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _selectedOutcome = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: _tr(
                  context,
                  '답변·필요 서류·기한·담당 부서·접수번호 메모',
                  'Answers, documents, deadlines, department, reference number',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      _controller.updateResult(_notes.text, _selectedOutcome);
                      unawaited(_controller.save());
                    },
              child: Text(_tr(context, '메모 저장', 'Save notes')),
            ),
            FilledButton(
              onPressed: busy ? null : () => _leave(complete: true),
              child: Text(
                _tr(context, '통화 마치고 기록 저장', 'Finish and save call record'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class CallRecordScreen extends ConsumerStatefulWidget {
  const CallRecordScreen({super.key, required this.record});
  final CallRecord record;
  @override
  ConsumerState<CallRecordScreen> createState() => _CallRecordState();
}

class _CallRecordState extends ConsumerState<CallRecordScreen> {
  late CallRecord _record;
  late final CallAudio _audio;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _audio = ref.read(callAudioFactoryProvider)();
  }

  @override
  void dispose() {
    unawaited(_audio.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _play(CallRecording clip) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await ref.read(callRepositoryProvider).recordingExists(clip.path)) {
        throw StateError('Missing recording');
      }
      await _audio.stopPlayback();
      await _audio.play(clip.path);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _tr(
            context,
            '녹음을 재생하지 못했어요. 파일이 없거나 재생할 수 없는 형식일 수 있어요.',
            'Could not play recording. The file may be missing or unsupported.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_tr(c, '통화 기록을 삭제할까요?', 'Delete this call record?')),
        content: Text(
          _tr(
            c,
            '준비 내용·메모·연결된 녹음 파일을 이 기기에서 삭제해요.',
            'Delete the preparation, notes, and attached audio from this device.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(_tr(c, '취소', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(_tr(c, '삭제', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _audio.stopPlayback();
      await ref.read(callRepositoryProvider).delete(_record.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _tr(
            context,
            '삭제하지 못했어요. 다시 시도해 주세요.',
            'Could not delete. Please retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget screen) async {
    await _audio.stopPlayback();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
    try {
      final saved = (await ref.read(callRepositoryProvider).load())
          .where((r) => r.id == _record.id)
          .firstOrNull;
      if (mounted && saved != null) setState(() => _record = saved);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _tr(
            context,
            '기록을 다시 불러오지 못했어요.',
            'Could not reload record.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => RehabPage(
    title: _tr(context, '통화 기록', 'Call record'),
    children: [
      Text(
        _record.organization,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      Text(_date(_record.createdAt)),
      if (_record.phone.isNotEmpty) SelectableText(_record.phone),
      const SizedBox(height: 12),
      Text(_record.purpose),
      if (_record.questions.isNotEmpty) SelectableText(_record.questions),
      const SizedBox(height: 16),
      Text(_outcome(context, _record.outcome)),
      if (_record.recordingIncomplete)
        Text(
          _tr(
            context,
            '녹음 중단·누락이 있는 통화예요. 전체 내용이 녹음된 것은 아니에요.',
            'Recording was interrupted or incomplete. The full call was not captured.',
          ),
        ),
      if (_record.notes.isNotEmpty) SelectableText(_record.notes),
      const SizedBox(height: 20),
      if (!_record.completed)
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () => _open(CallSessionScreen(record: _record)),
          icon: const Icon(Icons.phone_in_talk),
          label: Text(_tr(context, '이 준비로 통화 보조 열기', 'Open call controls')),
        ),
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _open(CallPreparationScreen(source: _record)),
        child: Text(_tr(context, '문의 내용을 새 준비에 복사', 'Copy into a new inquiry')),
      ),
      const Divider(height: 32),
      Text(
        _tr(context, '녹음 듣기', 'Listen to recordings'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (_record.recordings.isEmpty)
        Text(_tr(context, '저장된 녹음이 없어요.', 'No saved recordings.')),
      for (final clip in _record.recordings)
        Card(
          child: ListTile(
            title: Text(
              '${_date(clip.startedAt)} · ${_duration(clip.durationMs ~/ 1000)}',
            ),
            subtitle: clip.interrupted
                ? Text(
                    _tr(
                      context,
                      '중단된 구간 · 일부만 녹음됐을 수 있어요',
                      'Interrupted · may be incomplete',
                    ),
                  )
                : null,
            trailing: IconButton(
              tooltip: _tr(context, '녹음 재생', 'Play recording'),
              onPressed: _busy ? null : () => _play(clip),
              icon: const Icon(Icons.play_arrow),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            await _audio.stopPlayback();
          } catch (_) {
            if (mounted) {
              setState(
                () => _error = _tr(
                  context,
                  '재생을 중지하지 못했어요.',
                  'Could not stop playback.',
                ),
              );
            }
          }
        },
        icon: const Icon(Icons.stop),
        label: Text(_tr(context, '듣기 중지', 'Stop playback')),
      ),
      if (_error != null) _ErrorText(_error!),
      const SizedBox(height: 20),
      TextButton.icon(
        onPressed: _busy ? null : _delete,
        icon: const Icon(Icons.delete_outline),
        label: Text(_tr(context, '기록과 녹음 삭제', 'Delete record and audio')),
      ),
    ],
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}
