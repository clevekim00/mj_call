import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../model/call_record.dart';
import 'call_audio.dart';
import 'call_repository.dart';

class CallController extends ChangeNotifier {
  CallController({
    required this.record,
    required this.repository,
    required this.audio,
  });
  CallRecord record;
  final CallRepository repository;
  final CallAudio audio;
  bool recording = false,
      recordingBusy = false,
      speaking = false,
      saving = false;
  bool unsaved = false;
  String? error;
  int elapsedSeconds = 0;
  int _speechGeneration = 0;
  int _revision = 0;
  int _recordingGeneration = 0;
  Completer<void>? _startDone;
  bool _disposed = false, _checking = false;
  Timer? _timer;
  final _clock = Stopwatch();
  DateTime? _recordingStarted;
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> speak(String text) async {
    if (speaking || saving || text.trim().isEmpty) return;
    final generation = ++_speechGeneration;
    speaking = true;
    error = null;
    _emit();
    try {
      await audio.stopPlayback();
      // A stop requested while playback is stopping must cancel this utterance.
      if (generation != _speechGeneration || _disposed) return;
      await audio.speak(text.trim());
    } catch (_) {
      if (generation == _speechGeneration) {
        error = '음성을 재생하지 못했어요. 한국어 음성과 기기 음량을 확인해 주세요.';
      }
    } finally {
      if (generation == _speechGeneration) speaking = false;
      _emit();
    }
  }

  Future<void> stopSpeaking() async {
    ++_speechGeneration;
    try {
      await audio.stopSpeaking();
    } catch (_) {
      error = '말하기 중지에 실패했어요. 기기 음량을 낮추고 다시 눌러 주세요.';
    }
    speaking = false;
    _emit();
  }

  Future<void> startRecording({required bool consentConfirmed}) async {
    if (!consentConfirmed || recording || recordingBusy || saving || unsaved) {
      return;
    }
    recordingBusy = true;
    _startDone = Completer<void>();
    error = null;
    _emit();
    try {
      await audio.stopPlayback();
      await audio.startRecording('call_assist_${const Uuid().v4()}');
      _recordingStarted = DateTime.now();
      _clock.reset();
      _clock.start();
      elapsedSeconds = 0;
      recording = true;
      _recordingGeneration++;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (_) {
      error = '녹음을 시작하지 못했어요. 마이크 권한과 기기 저장 공간을 확인해 주세요.';
    } finally {
      recordingBusy = false;
      _startDone?.complete();
      _startDone = null;
      _emit();
    }
  }

  Future<void> _tick() async {
    elapsedSeconds = _clock.elapsed.inSeconds;
    _emit();
    if (_checking || recordingBusy || !recording) return;
    _checking = true;
    final generation = _recordingGeneration;
    try {
      if (!await audio.isRecording() &&
          generation == _recordingGeneration &&
          recording &&
          !recordingBusy) {
        await stopRecording(interrupted: true);
      }
    } catch (_) {
      if (generation == _recordingGeneration && recording && !recordingBusy) {
        await stopRecording(interrupted: true);
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> stopRecording({bool interrupted = false}) async {
    if (!recording || recordingBusy) return;
    recordingBusy = true;
    _recordingGeneration++;
    _timer?.cancel();
    _clock.stop();
    _emit();
    try {
      final path = await audio.stopRecording();
      recording = false;
      if (interrupted) record = record.copyWith(recordingIncomplete: true);
      if (path == null || !await repository.recordingExists(path)) {
        record = record.copyWith(recordingIncomplete: true);
        _revision++;
        unsaved = true;
        await save();
        error = '녹음 파일을 확인하지 못했어요. 이번 구간은 저장되지 않았을 수 있어요.';
        return;
      }
      record = record.copyWith(
        recordings: [
          ...record.recordings,
          CallRecording(
            path: path,
            startedAt: _recordingStarted!,
            durationMs: _clock.elapsedMilliseconds,
            interrupted: interrupted,
          ),
        ],
      );
      _revision++;
      unsaved = true;
      await save();
      if (interrupted && !unsaved) {
        error = '녹음이 중단되어 가능한 구간을 저장했어요. 다시 시작하려면 녹음 버튼을 눌러 주세요.';
      }
    } catch (_) {
      recording = false;
      record = record.copyWith(recordingIncomplete: true);
      _revision++;
      unsaved = true;
      error = '녹음 종료 또는 저장에 실패했어요. 저장 상태를 확인해 주세요.';
    } finally {
      recordingBusy = false;
      _emit();
    }
  }

  void updateResult(String notes, String outcome) {
    record = record.copyWith(notes: notes, outcome: outcome);
    _revision++;
    unsaved = true;
  }

  Future<bool> save({bool complete = false}) async {
    if (saving) return false;
    saving = true;
    _emit();
    try {
      final revision = _revision;
      final next = record.copyWith(completed: complete || record.completed);
      await repository.save(next);
      if (revision == _revision) {
        record = next;
        unsaved = false;
      } else {
        record = record.copyWith(completed: next.completed);
        unsaved = true;
      }
      error = null;
      return !unsaved;
    } catch (_) {
      unsaved = true;
      error = '기록을 저장하지 못했어요. 이 화면에서 저장을 다시 눌러 주세요.';
      return false;
    } finally {
      saving = false;
      _emit();
    }
  }

  Future<void> interrupt() async {
    await stopSpeaking();
    // A background transition during the OS permission dialog must not leave
    // a newly started recording running after the screen is hidden.
    await _startDone?.future;
    if (recording) await stopRecording(interrupted: true);
    try {
      await audio.stopPlayback();
    } catch (_) {
      /* Surface on next play. */
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _speechGeneration++;
    _timer?.cancel();
    unawaited(audio.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
