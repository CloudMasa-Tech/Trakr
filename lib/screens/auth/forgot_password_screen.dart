import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../firebase/firebase_context_provider.dart';
import '../../providers/auth_session_provider.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme_colors.dart';
import 'auth_shared.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({
    super.key,
    this.initialEmail,
  });

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _emailSent = false;
  bool _isSending = false;

  late final AnimationController _checkAnimCtrl;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail ?? '';

    _checkAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkScale = CurvedAnimation(
      parent: _checkAnimCtrl,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _checkAnimCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      final email = _emailCtrl.text.trim();
      await context.read<AuthSessionProvider>().sendPasswordResetEmail(email);

      // Trigger push notification to the user about password reset
      try {
        await NotificationService().sendNotificationToUser(
          identifier: email,
          title: 'Password Reset Initiated',
          body:
              'A password reset link was sent to $email. Please check your email and reset your password.',
        );

        // Also add to notifications in firestore
        await FirebaseContextProvider.current.firestore
            .collection('notifications')
            .add({
          'recipient': email,
          'type': 'Security',
          'content': 'Password reset link sent to $email.',
          'status': 'Sent',
          'suppressFirestorePush': true,
          'allowFirestorePush': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error triggering forgot password notification: $e');
      }

      if (!mounted) return;
      setState(() {
        _emailSent = true;
        _isSending = false;
      });
      _checkAnimCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.dark.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _isSending = true);
    try {
      final email = _emailCtrl.text.trim();
      await context.read<AuthSessionProvider>().sendPasswordResetEmail(email);

      // Trigger push notification to the user about password reset
      try {
        await NotificationService().sendNotificationToUser(
          identifier: email,
          title: 'Password Reset Initiated',
          body:
              'A password reset link was sent to $email. Please check your email and reset your password.',
        );

        // Also add to notifications in firestore
        await FirebaseContextProvider.current.firestore
            .collection('notifications')
            .add({
          'recipient': email,
          'type': 'Security',
          'content': 'Password reset link sent to $email.',
          'status': 'Sent',
          'suppressFirestorePush': true,
          'allowFirestorePush': false,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('Error triggering forgot password notification: $e');
      }

      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  color: AppThemeColors.darkText, size: 18),
              SizedBox(width: 8),
              Text('Reset email sent again!'),
            ],
          ),
          backgroundColor: AppColors.dark.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.dark.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _emailSent ? _buildSuccessCard() : _buildFormCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      key: const ValueKey('form'),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: authCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.overlay,
            blurRadius: 48,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AuthBrandHeader(),
            const SizedBox(height: 2),

            // Title
            const Center(
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: authNavy,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Description
            const Center(
              child: Text(
                'Enter your registered email address and we\'ll send you\na link to reset your password.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: authSubtext,
                  fontSize: 13.5,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Email field
            LabeledField(
              label: 'Email Address',
              child: TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: authNavy, fontSize: 14),
                decoration: authInputDecoration(
                  'Enter your registered email',
                  prefixIcon: Icons.email_outlined,
                ),
                onFieldSubmitted: (_) => _sendResetEmail(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Email is required';
                  }
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 24),

            // Send reset link button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSending ? null : _sendResetEmail,
                style: FilledButton.styleFrom(
                  backgroundColor: authSky,
                  foregroundColor: AppColors.dark.onPrimary,
                  disabledBackgroundColor: authSky.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: AppThemeColors.darkText,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Send Reset Link',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 20),

            // Back to login
            Center(
              child: TextButton.icon(
                onPressed: _goToLogin,
                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                label: const Text('Back to Login'),
                style: TextButton.styleFrom(
                  foregroundColor: authSubtext,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      key: const ValueKey('success'),
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: authCard,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.dark.overlay,
            blurRadius: 48,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          const AuthBrandHeader(),
          const SizedBox(height: 8),

          // Animated check icon
          ScaleTransition(
            scale: _checkScale,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.dark.success, AppColors.dark.onSuccess],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.dark.success.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.mark_email_read_rounded,
                color: AppThemeColors.darkText,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 28),

          const Text(
            'Check Your Email',
            style: TextStyle(
              color: authNavy,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),

          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(
                color: authSubtext,
                fontSize: 13.5,
                height: 1.7,
              ),
              children: [
                const TextSpan(
                  text: 'We\'ve sent a password reset link to\n',
                ),
                TextSpan(
                  text: _emailCtrl.text.trim(),
                  style: const TextStyle(
                    color: authNavy,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Resend link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Still didn\'t receive it? ',
                style: TextStyle(
                  color: authSubtext,
                  fontSize: 13,
                ),
              ),
              TextButton(
                onPressed: _isSending ? null : _resendEmail,
                style: TextButton.styleFrom(
                  foregroundColor: authSky,
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Resend Email'),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Return to login
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _goToLogin,
              icon: const Icon(Icons.login_rounded, size: 18),
              label: const Text(
                'Return to Login',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: authSky,
                foregroundColor: AppColors.dark.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
