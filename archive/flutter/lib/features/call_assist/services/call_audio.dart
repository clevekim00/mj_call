import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_rehab/services/audio/audio_recorder_service.dart';
import 'package:speech_rehab/services/audio/audio_player_service.dart';

abstract class CallAudio {
  Future<void> speak(String text);
  Future<void> stopSpeaking();
  Future<void> startRecording(String fileName);
  Future<String?> stopRecording();
  Future<bool> isRecording();
  Future<void> play(String path);
  Future<void> stopPlayback();
  Future<void> dispose();
}

/// Dedicated ownership: leaving a call never stops another screen's TTS later.
class DeviceCallAudio implements CallAudio {
  static const _ttsChannel = MethodChannel('speech_rehab/tts');
  final _recorder = AudioRecorderService();
  final _nativePlayer = AudioPlayerService();
  AudioPlayer? _desktopPlayer;
  FlutterTts? _tts;
  Future<void>? _ttsReady;
  bool get _nativePlayback => Platform.isIOS || Platform.isMacOS;

  Future<void> _initTts() async {
    try {
      _tts = FlutterTts();
      final available = await _tts!.isLanguageAvailable('ko-KR');
      if (available != true && available != 1) {
        throw StateError('Install a Korean system voice');
      }
      if (await _tts!.setLanguage('ko-KR') == 0) {
        throw StateError('Korean voice could not be selected');
      }
      await _tts!.setSpeechRate(0.42);
      await _tts!.setVolume(1);
      await _tts!.awaitSpeakCompletion(true);
    } catch (_) {
      // Allow retry after the user installs/enables a system voice.
      _ttsReady = null;
      rethrow;
    }
  }

  @override
  Future<void> speak(String text) async {
    if (Platform.isIOS) {
      await _ttsChannel.invokeMethod<void>('callSpeak', {'text': text});
    } else {
      await (_ttsReady ??= _initTts());
      final result = await _tts!.speak(text);
      if (result == 0) throw StateError('Speech could not start');
    }
  }

  @override
  Future<void> stopSpeaking() async {
    if (Platform.isIOS) {
      await _ttsChannel.invokeMethod<void>('callStop');
    } else {
      if (_ttsReady != null) await _ttsReady;
      await _tts?.stop();
    }
  }

  @override
  Future<void> startRecording(String fileName) =>
      _recorder.startRecording(fileName);
  @override
  Future<String?> stopRecording() => _recorder.stopRecording();
  @override
  Future<bool> isRecording() => _recorder.checkIsRecording();
  @override
  Future<void> play(String path) async {
    if (_nativePlayback) {
      await _nativePlayer.playFile(path);
    } else {
      _desktopPlayer ??= AudioPlayer();
      await _desktopPlayer!.play(DeviceFileSource(path));
    }
  }

  @override
  Future<void> stopPlayback() async {
    if (_nativePlayback) {
      await _nativePlayer.stop();
    } else {
      await _desktopPlayer?.stop();
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await stopSpeaking();
    } finally {
      try {
        await stopPlayback();
      } finally {
        await _recorder.dispose();
        await _desktopPlayer?.dispose();
      }
    }
  }
}
