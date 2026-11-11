import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Three calm sound effects generated in code (no audio files needed).
class Sfx {
  static bool enabled = true;
  static final AudioPlayer _player = AudioPlayer();
  static Uint8List? _send;
  static Uint8List? _recv;
  static Uint8List? _tap;

  static Uint8List _wav(List<List<double>> notes) {
    const sr = 22050;
    final samples = <int>[];
    for (final n in notes) {
      final cnt = (n[1] * sr).round();
      for (var i = 0; i < cnt; i++) {
        final t = i / sr;
        final attack = min(1.0, i / (sr * 0.01));
        final decay = pow(1 - i / cnt, 2.0).toDouble();
        final v = (sin(2 * pi * n[0] * t) * 0.6 + sin(2 * pi * n[0] * 2 * t) * 0.15) * attack * decay * 0.5;
        samples.add((v * 32767).round());
      }
    }
    final data = ByteData(44 + samples.length * 2);
    void str(int o, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(o + i, s.codeUnitAt(i));
      }
    }

    str(0, 'RIFF');
    data.setUint32(4, 36 + samples.length * 2, Endian.little);
    str(8, 'WAVE');
    str(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sr, Endian.little);
    data.setUint32(28, sr * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    str(36, 'data');
    data.setUint32(40, samples.length * 2, Endian.little);
    for (var i = 0; i < samples.length; i++) {
      data.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<void> _play(Uint8List bytes) async {
    if (!enabled) return;
    try {
      await _player.stop();
      await _player.play(BytesSource(bytes), volume: 0.6);
    } catch (_) {}
  }

  static Future<void> send() => _play(_send ??= _wav([[523.25, 0.12], [659.25, 0.18]]));
  static Future<void> receive() => _play(_recv ??= _wav([[659.25, 0.14], [783.99, 0.14], [987.77, 0.28]]));
  static Future<void> tap() => _play(_tap ??= _wav([[440.0, 0.09]]));
}
