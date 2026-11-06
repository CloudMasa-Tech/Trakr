import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_session_provider.dart';
import '../../theme/app_theme_colors.dart';
import 'auth_shared.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? initialEmail;

  const LoginScreen({
    super.key,
    this.initialEmail,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  int _buildCount = 0;

  @override
  void initState() {
    super.initState();
    AuthSessionProvider.timingLog(
        'LoginScreen.initState (first mount or re-mount)');
    _emailCtrl.text = widget.initialEmail ?? '';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthSessionProvider>();
      if (auth.errorMessage != null) {
        _showLoginFailure(auth.errorMessage!);
      }
    });
  }

  @override
  void dispose() {
    AuthSessionProvider.timingLog('LoginScreen.dispose');
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // Reset the login-timing anchor — "Sign in" was tapped. Every boundary in
    // the login chain logs `[LOGIN_TIMING] ... elapsed=` relative to this point.
    AuthSessionProvider.markLoginStart();

    try {
      final auth = context.read<AuthSessionProvider>();
      await auth.signIn(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );

      if (!mounted) return;

      // Tells the browser/password manager the sign-in succeeded so it can
      // offer to save these credentials.
      TextInput.finishAutofillContext();

      // Navigate directly to the workspace dashboard when we have the slug,
      // instead of relying on the router's redirect which may not fire if
      // the auth state hasn't fully propagated. This also avoids a full
      // page reload to index.html that could occur with the redirect path.
      final slug = auth.workspaceSlug;
      final role = auth.role;
      if (slug != null && slug.isNotEmpty && role != null && role != AppUserRole.superAdmin) {
        AuthSessionProvider.timingLog(
            'login_screen: navigating to /workspace/$slug/dashboard (role=${role.value})');
        context.go('/workspace/$slug/dashboard');
      } else {
        AuthSessionProvider.timingLog(
            'login_screen: navigating to / (role=${role?.value}, slug=$slug)');
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      await _showLoginFailure(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Picks a heading that matches the failure.
  ///
  /// Every sign-in failure used to be headed "Invalid Credentials", including
  /// the ones that have nothing to do with credentials — a dropped
  /// connection, a workspace still being provisioned, a rate-limit, a
  /// disabled account. Telling someone their password is wrong when their
  /// Wi-Fi dropped sends them off resetting a password that was fine.
  ({String title, IconData icon}) _classifyLoginError(String message) {
    final m = message.toLowerCase();
    if (m.contains('network') ||
        m.contains('connection') ||
        m.contains('timed out') ||
        m.contains('unavailable') ||
        m.contains('unreachable')) {
      return (title: 'Connection Problem', icon: Icons.wifi_off_rounded);
    }
    if (m.contains('being set up') ||
        m.contains('not ready') ||
        m.contains('try again shortly') ||
        m.contains('few minutes')) {
      return (title: 'Workspace Not Ready', icon: Icons.hourglass_top_rounded);
    }
    if (m.contains('suspended') || m.contains('disabled')) {
      return (title: 'Account Unavailable', icon: Icons.block_rounded);
    }
    if (m.contains('too many')) {
      return (title: 'Too Many Attempts', icon: Icons.timer_outlined);
    }
    if (m.contains('not enabled') ||
        m.contains('not authorized') ||
        m.contains('api key') ||
        m.contains('internal error')) {
      return (title: 'Sign-in Unavailable', icon: Icons.build_circle_outlined);
    }
    return (title: 'Invalid Credentials', icon: Icons.error_outline_rounded);
  }

  Future<void> _showLoginFailure(String message) {
    final kind = _classifyLoginError(message);
    return _showLoginMessageDialog(
      title: kind.title,
      message: message,
      icon: kind.icon,
      iconColor: AppColors.dark.error,
    );
  }

  Future<void> _showLoginMessageDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color iconColor,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthSessionProvider>();
    _buildCount++;
    AuthSessionProvider.timingLog(
        'LoginScreen.build #$_buildCount | isLoading=${auth.isLoading} '
        'isAuthenticated=${auth.isAuthenticated} role=${auth.role?.value ?? 'null'} '
        'user=${auth.user?.email ?? 'null'} error=${auth.errorMessage != null}');
    final formCard = AuthFormCard(
      header: const AuthBrandHeader(),
      title: 'Login',
      subtitle: 'Empowering teams through digital attendance.',
      titleAlign: TextAlign.center,
      headerGap: 10,
      form: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (!auth.isLoading) {
                  _submit();
                }
                return null;
              },
            ),
          },
          child: Form(
            key: _formKey,
            // Lets the browser / password manager offer saved credentials and
            // save new ones — on a daily-use web app this is the difference
            // between typing an email every morning and one click.
            child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LabeledField(
                  label: 'Email',
                  child: TextFormField(
                    controller: _emailCtrl,
                    autofocus: true,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: authNavy, fontSize: 14),
                    decoration: authInputDecoration(
                      'Enter your email',
                      prefixIcon: Icons.email_outlined,
                    ),
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_passwordFocus);
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!value.contains('@')) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'Password',
                  child: TextFormField(
                    controller: _passwordCtrl,
                    focusNode: _passwordFocus,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: authNavy, fontSize: 14),
                    decoration: authInputDecoration(
                      'Enter your password',
                      prefixIcon: Icons.lock_outline_rounded,
                    ).copyWith(
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          color: authSubtext,
                          size: 20,
                        ),
                      ),
                    ),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: auth.isLoading
                        ? null
                        : () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ForgotPasswordScreen(
                                  initialEmail:
                                      _emailCtrl.text.trim().isNotEmpty
                                          ? _emailCtrl.text.trim()
                                          : null,
                                ),
                              ),
                            );
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: authSky,
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Forgot Password?'),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: auth.isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: authSky,
                      foregroundColor: AppColors.dark.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      auth.isLoading ? 'Signing in...' : 'Login',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppBackground(
        forceDark: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: formCard,
            ),
          ),
        ),
      ),
    );
  }
}
