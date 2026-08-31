/// Native stub for [playScanBeep].
///
/// Native platforms use [HapticFeedback] instead of audio; see
/// `staff_scan_qr_screen.dart`. The web implementation lives in
/// `scan_sound_web.dart` and is selected via a `dart.library.html`
/// conditional import so `package:web` is never compiled into the native
/// toolchain.
void playScanBeep({bool short = false}) {}