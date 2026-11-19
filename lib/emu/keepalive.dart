import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

import 'session.dart';

/// Giữ app chạy khi chuyển sang app khác (iOS): phát âm thanh im lặng ở chế độ nền "audio"
/// trong lúc còn game chạy. Dừng ngay khi không còn game nào.
class KeepAlive with WidgetsBindingObserver {
  static final KeepAlive _i = KeepAlive._();
  KeepAlive._();

  /// App đang ở foreground? Khi false, giả lập không vẽ khung hình (iOS cấm dùng GPU nền).
  static bool active = true;

  AudioPlayer? _p;
  bool _on = false;

  static void init() {
    WidgetsBinding.instance.addObserver(_i);
    EmuRuntime.changed.addListener(_i._sync);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    active = s == AppLifecycleState.resumed;
    if (active) {
      for (final e in EmuRuntime.sessions.values) {
        e.resume();
      }
    }
    _sync();
  }

  Future<void> _sync() async {
    if (!Platform.isIOS) return;
    final need = EmuRuntime.sessions.isNotEmpty;
    try {
      if (need && !_on) {
        _on = true;
        final p = _p ??= AudioPlayer();
        await p.setAudioContext(AudioContext(
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback, options: {AVAudioSessionOptions.mixWithOthers}),
        ));
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(0.01);
        await p.play(AssetSource('silence.wav'));
      } else if (!need && _on) {
        _on = false;
        await _p?.stop();
      } else if (need && _on && _p?.state != PlayerState.playing && active == false) {
        await _p?.resume();
      }
    } catch (_) {
      _on = false;
    }
  }
}
