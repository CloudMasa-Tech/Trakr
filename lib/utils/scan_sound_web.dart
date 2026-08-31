import 'package:web/web.dart' as web;

/// Plays a short Web Audio beep through the browser.
///
/// Best-effort: browsers may suspend the AudioContext until a user gesture,
/// in which case the beep is silently skipped.
void playScanBeep({bool short = false}) {
  try {
    final web.AudioContext context = web.AudioContext();
    final web.OscillatorNode oscillator = context.createOscillator();
    final web.GainNode gain = context.createGain();
    oscillator.frequency.value = short ? 1100 : 1318.5;
    gain.gain.value = 0.0001;
    oscillator.connect(gain);
    gain.connect(context.destination);
    final start = context.currentTime + 0.01;
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(0.16, start + 0.015);
    gain.gain.exponentialRampToValueAtTime(
      0.0001,
      start + (short ? 0.09 : 0.16),
    );
    oscillator.start(start);
    oscillator.stop(start + (short ? 0.11 : 0.18));
  } catch (_) {
    // Web Audio is best-effort (autoplay policies may suspend it); ignore.
  }
}