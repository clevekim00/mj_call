import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_rehab/features/call_assist/model/call_record.dart';
import 'package:speech_rehab/features/call_assist/services/call_audio.dart';
import 'package:speech_rehab/features/call_assist/services/call_controller.dart';
import 'package:speech_rehab/features/call_assist/services/call_repository.dart';
import 'package:speech_rehab/features/call_assist/view/call_assist_screens.dart';
import 'package:speech_rehab/features/practice/view/practice_mode_selection_screen.dart';

CallRecord plan() => CallRecord(
  id: 'test-call',
  createdAt: DateTime(2026, 11, 2),
  organization: '주민센터',
  purpose: '신청 절차 문의',
  questions: '필요한 서류가 무엇인가요?',
);

class FakeAudio implements CallAudio {
  List<String> spoken = [];
  bool capturing = false, disposed = false;
  int starts = 0, stops = 0;
  String? recordingPath = '/test/call_assist_clip.m4a';
  Completer<void>? playbackGate, speechGate, startGate;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    await speechGate?.future;
  }

  @override
  Future<void> stopSpeaking() async {
    if (speechGate != null && !speechGate!.isCompleted) speechGate!.complete();
  }

  @override
  Future<void> startRecording(String fileName) async {
    starts++;
    await startGate?.future;
    capturing = true;
  }

  @override
  Future<String?> stopRecording() async {
    capturing = false;
    stops++;
    return recordingPath;
  }

  @override
  Future<bool> isRecording() async => capturing;
  @override
  Future<void> play(String path) async {}
  @override
  Future<void> stopPlayback() async {
    await playbackGate?.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class MemoryRepository extends CallRepository {
  List<CallRecord> records = [];
  bool failSave = false;
  Completer<void>? saveGate;
  @override
  Future<List<CallRecord>> load() async => records;
  @override
  Future<bool> recordingExists(String path) async => true;
  @override
  Future<void> save(CallRecord record) async {
    await saveGate?.future;
    if (failSave) throw StateError('disk full');
    records.removeWhere((r) => r.id == record.id);
    records.add(record);
  }
}

class TestPaths extends PathProviderPlatform {
  TestPaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'device speech refuses a missing Korean voice and can retry after installation',
    () async {
      const channel = MethodChannel('flutter_tts');
      const player = MethodChannel('speech_rehab/audio_player');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var available = false, speaks = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isLanguageAvailable') return available;
        if (call.method == 'speak') speaks++;
        return 1;
      });
      messenger.setMockMethodCallHandler(player, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(player, null);
      });
      final audio = DeviceCallAudio();
      await expectLater(audio.speak('문의합니다.'), throwsStateError);
      expect(speaks, 0);
      available = true;
      await audio.speak('문의합니다.');
      expect(speaks, 1);
      await audio.dispose();
    },
  );

  test(
    'cancel while waiting for playback never emits a late utterance',
    () async {
      final audio = FakeAudio()..playbackGate = Completer<void>();
      final c = CallController(
        record: plan(),
        repository: MemoryRepository(),
        audio: audio,
      );
      final speak = c.speak('잠시만 기다려 주세요.');
      await c.stopSpeaking();
      audio.playbackGate!.complete();
      await speak;
      expect(audio.spoken, isEmpty);
      expect(c.speaking, false);
      c.dispose();
    },
  );

  test(
    'recording needs consent and a failed save retains audio for retry',
    () async {
      final audio = FakeAudio();
      final repo = MemoryRepository();
      final c = CallController(record: plan(), repository: repo, audio: audio);
      await c.startRecording(consentConfirmed: false);
      expect(audio.starts, 0);
      await c.startRecording(consentConfirmed: true);
      expect(c.recording, true);
      repo.failSave = true;
      await c.stopRecording();
      expect(c.recording, false);
      expect(c.unsaved, true);
      expect(c.record.recordings.single.path, audio.recordingPath);
      repo.failSave = false;
      expect(await c.save(), true);
      expect(repo.records.single.recordings, hasLength(1));
      c.dispose();
    },
  );

  test(
    'background transition during microphone setup stops the new capture',
    () async {
      final audio = FakeAudio()..startGate = Completer<void>();
      final repo = MemoryRepository();
      final c = CallController(record: plan(), repository: repo, audio: audio);
      final start = c.startRecording(consentConfirmed: true);
      await Future<void>.delayed(Duration.zero);
      final interrupt = c.interrupt();
      audio.startGate!.complete();
      await start;
      await interrupt;
      expect(c.recording, false);
      expect(audio.stops, 1);
      expect(repo.records.single.recordings.single.interrupted, true);
      expect(repo.records.single.recordingIncomplete, true);
      c.dispose();
    },
  );

  test(
    'missing recording persists an incomplete warning without a fake clip',
    () async {
      final audio = FakeAudio()..recordingPath = null;
      final repo = MemoryRepository();
      final c = CallController(record: plan(), repository: repo, audio: audio);
      await c.startRecording(consentConfirmed: true);
      await c.stopRecording();
      expect(repo.records.single.recordingIncomplete, true);
      expect(repo.records.single.recordings, isEmpty);
      expect(c.error, isNotNull);
      c.dispose();
    },
  );

  test('editing during an in-flight save preserves the newer notes', () async {
    final repo = MemoryRepository()..saveGate = Completer<void>();
    final c = CallController(
      record: plan(),
      repository: repo,
      audio: FakeAudio(),
    );
    c.updateResult('old', 'partial');
    final save = c.save();
    c.updateResult('new', 'waiting');
    repo.saveGate!.complete();
    expect(await save, false);
    expect(c.unsaved, true);
    expect(c.record.notes, 'new');
    repo.saveGate = null;
    await c.save();
    expect(repo.records.single.notes, 'new');
    c.dispose();
  });

  test(
    'repository survives reload, preserves corrupt data, and deletes owned audio',
    () async {
      final root = await Directory.systemTemp.createTemp('call-assist-test-');
      final old = PathProviderPlatform.instance;
      PathProviderPlatform.instance = TestPaths(root.path);
      addTearDown(() async {
        PathProviderPlatform.instance = old;
        await root.delete(recursive: true);
      });
      final dir = await Directory('${root.path}/recordings').create();
      final file = await File(
        '${dir.path}/call_assist_owned.m4a',
      ).writeAsBytes([1, 2, 3]);
      final record = plan().copyWith(
        notes: '서류 확인',
        outcome: 'answered',
        completed: true,
        recordings: [
          CallRecording(
            path: file.path,
            startedAt: DateTime.now(),
            durationMs: 1000,
          ),
        ],
      );
      await CallRepository().save(record);
      expect((await CallRepository().load()).single.notes, '서류 확인');
      await CallRepository().delete(record.id);
      expect(await file.exists(), false);
      expect(await CallRepository().load(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CallRepository.storageKey, 'broken');
      await expectLater(CallRepository().save(plan()), throwsFormatException);
      expect(prefs.getString(CallRepository.storageKey), 'broken');
    },
  );

  testWidgets('today menu leads to inquiry preparation and persists it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PracticeModeSelectionScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('통화 도우미'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 통화 준비'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '주민센터');
    await tester.enterText(find.byType(TextFormField).at(2), '신청 절차 문의');
    await tester.scrollUntilVisible(
      find.text('준비만 저장'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('준비만 저장'));
    await tester.pumpAndSettle();
    expect((await CallRepository().load()).single.organization, '주민센터');
    expect(find.text('주민센터'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'call controls require phone readiness and recording permission',
    (tester) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = FakeAudio();
      final repo = MemoryRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            callRepositoryProvider.overrideWithValue(repo),
            callAudioFactoryProvider.overrideWithValue(() => audio),
          ],
          child: MaterialApp(home: CallSessionScreen(record: plan())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('call-text-input')),
        '서류를 알려 주세요.',
      );
      final speak = find.byKey(const Key('call-speak-text'));
      expect(tester.widget<FilledButton>(speak).onPressed, isNull);
      await tester.tap(find.byKey(const Key('call-phone-ready')));
      await tester.pump();
      await tester.ensureVisible(speak);
      await tester.tap(speak);
      await tester.pumpAndSettle();
      expect(audio.spoken, ['서류를 알려 주세요.']);
      final recordButton = find.byKey(const Key('call-record-toggle'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('call-record-consent')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        recordButton,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(recordButton).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('call-record-consent')));
      await tester.tap(find.byKey(const Key('call-record-consent')));
      await tester.pump();
      await tester.ensureVisible(recordButton);
      await tester.tap(recordButton);
      await tester.pump();
      expect(audio.capturing, true);
      await tester.tap(recordButton);
      await tester.pumpAndSettle();
      expect(repo.records.single.recordings, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('compact call screen with 200% text keeps stop accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [callAudioFactoryProvider.overrideWithValue(FakeAudio.new)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: CallSessionScreen(record: plan()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('call-stop-speech')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
