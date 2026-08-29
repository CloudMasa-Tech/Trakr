import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:attendqr/theme/app_theme_colors.dart';
import 'package:attendqr/screens/auth/login_screen.dart';
import 'package:attendqr/widgets/common/trakr_logo.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
//
// These constants intentionally mirror the app's real dark-theme tokens defined
// in `lib/theme/app_theme_colors.dart` (AppColors.dark). The landing page is an
// always-dark marketing surface (shown pre-auth on web), so we reference the
// same hex values the dashboard/sidebar/buttons use rather than inventing new
// colors. The primary CTA gradient reuses AppThemeColors.actionGradient.
// ─────────────────────────────────────────────────────────────────────────────
const _bg = Color(0xFF07151D); // AppColors.dark.background
const _bgDeep = Color(0xFF04101A); // deeper navy for gradient base
const _surface = Color(0xFF0E2633); // AppColors.dark.surface
const _surfaceRaised = Color(0xFF13303F); // AppColors.dark.surfaceRaised
const _accent = Color(0xFF0F766E); // AppColors.dark.primary  (teal)
const _accentBright = Color(0xFF34D399); // AppColors.dark.success (emerald)
const _accentAlt = Color(0xFF22D3EE); // AppColors.dark.focus   (cyan)
const _onAccent = Color(0xFFFFFFFF); // AppColors.dark.onPrimary
const _text = Color(0xFFF2F7FA); // AppColors.dark.textPrimary
const _text2 = Color(0xFFB7C7D3); // AppColors.dark.textSecondary
const _muted = Color(0xFF93A9B9); // AppColors.dark.textMuted
const _border = Color(0xFF2A5568); // AppColors.dark.border
const _secondary = Color(0xFFFF9F45); // AppColors.dark.secondary (warm accent)

// Warm accent gradient — Tailwind `from-red-500 to-orange-500` — applied to
// headings / emphasized text via ShaderMask (the Flutter equivalent of
// `bg-clip-text text-transparent`). Mirrors AppThemeColors.headingGradient.
const _warmGradient = LinearGradient(
  colors: [Color(0xFFEF4444), Color(0xFFF97316)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// Brighter variant of the cool button gradient for hover/focus states
// (Tailwind `from-teal-700 via-cyan-800 to-blue-900`, brightened).
const _coolGradientHover = LinearGradient(
  colors: [Color(0xFF159C8F), Color(0xFF1F7C92), Color(0xFF2C4FA8)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// PLACEHOLDER LINK — replace with the real TRAKR documentation URL before launch.
const String kDocsUrl = 'https://docs.trakr.example.com';

Future<void> _openExternal(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _featuresKey = GlobalKey();
  final _showcaseKey = GlobalKey();
  final _statsKey = GlobalKey();
  final _testimonialsKey = GlobalKey();
  final _pricingKey = GlobalKey();
  final _demoKey = GlobalKey();
  late final AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat(reverse: true);
  }

  void _goToLogin() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    return Theme(
      data: baseTheme.copyWith(
        scaffoldBackgroundColor: _bg,
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
          bodyColor: _text,
          displayColor: _text,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(),
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              const Positioned.fill(child: _PageBackdrop()),
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Column(
                    children: [
                      const SizedBox(height: 96),
                      _HeroSection(
                        onStartTrial: _goToLogin,
                        onBookDemo: () => _scrollTo(_demoKey),
                      ),
                      const _TrustedByStrip(),
                      _FeatureSection(key: _featuresKey),
                      _ProductShowcaseSection(key: _showcaseKey),
                      const _HowItWorksSection(),
                      _StatsBand(key: _statsKey),
                      _TestimonialsSection(key: _testimonialsKey),
                      _PricingSection(key: _pricingKey),
                      _DemoCtaBand(key: _demoKey, onStartTrial: _goToLogin),
                      const _SiteFooter(),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _NavBar(
                  onLogin: _goToLogin,
                  onFeatures: () => _scrollTo(_featuresKey),
                  onPricing: () => _scrollTo(_pricingKey),
                  onDocs: () => _openExternal(kDocsUrl),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKDROP — deep navy gradient base + slow-drifting teal/emerald/cyan glow
// meshes for depth (CSS-gradient/blur over heavy imagery, per perf guidance).
// ─────────────────────────────────────────────────────────────────────────────
class _PageBackdrop extends StatefulWidget {
  const _PageBackdrop();

  @override
  State<_PageBackdrop> createState() => _PageBackdropState();
}

class _PageBackdropState extends State<_PageBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 9000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg, _bgDeep],
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Stack(
              children: [
                Positioned(
                  top: -160 + t * 60,
                  left: -120,
                  child: _Glow(color: _accent.withValues(alpha: .20), size: 520),
                ),
                Positioned(
                  top: 220 - t * 80,
                  right: -160,
                  child: _Glow(
                      color: _accentBright.withValues(alpha: .14), size: 480),
                ),
                Positioned(
                  bottom: -120 + t * 70,
                  left: MediaQuery.of(context).size.width * .35,
                  child: _Glow(
                      color: _accentAlt.withValues(alpha: .12), size: 420),
                ),
                // subtle dotted grid overlay
                const Opacity(
                  opacity: .04,
                  child: CustomPaint(
                    painter: _DotGridPainter(color: _text),
                    size: Size.infinite,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  const _Glow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  final Color color;
  const _DotGridPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const step = 26.0;
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS + BUTTON PRIMITIVES
// ─────────────────────────────────────────────────────────────────────────────
BoxDecoration _glassDecoration({
  Color? fill,
  double fillOpacity = .55,
  Color borderColor = _border,
  double borderOpacity = .22,
  double radius = 18,
}) =>
    BoxDecoration(
      color: (fill ?? _surface).withValues(alpha: fillOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor.withValues(alpha: borderOpacity)),
    );

class _GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double fillOpacity;

  const _GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(26),
    this.fillOpacity = .5,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: padding,
          decoration: _glassDecoration(fillOpacity: fillOpacity),
          child: child,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final VoidCallback onPressed;
  final IconData? icon;
  final String label;
  final bool compact;
  const _PrimaryButton({
    required this.onPressed,
    this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final gradient =
        _hovered ? _coolGradientHover : AppThemeColors.actionGradient;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: (_hovered ? _accentAlt : _accent).withValues(alpha: .5),
              blurRadius: _hovered ? 30 : 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 20 : 28,
                vertical: widget.compact ? 14 : 17,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: widget.compact ? 18 : 20, color: _onAccent),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: _onAccent,
                      fontSize: widget.compact ? 15 : 16.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData? icon;
  final String label;
  const _SecondaryButton({
    required this.onPressed,
    this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 17),
          decoration: _glassDecoration(fillOpacity: .35, radius: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: _text, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: _text,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  const _NavButton(this.label, this.onPressed);

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final color = _hovered ? _accentBright : _text2;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: TextButton(
        onPressed: widget.onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: const TextStyle(
              fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: .2),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: TextStyle(
              color: color, fontSize: 15.5, fontWeight: FontWeight.w600),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

class _BrandMark extends StatefulWidget {
  final double size;
  const _BrandMark({required this.size});
  @override
  State<_BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<_BrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: .85, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.size * .22),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: .35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * .22),
          child: TrakrLogo(size: widget.size),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SCROLL REVEAL
// ─────────────────────────────────────────────────────────────────────────────
class _Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset offset;
  const _Reveal({
    required this.child,
    this.delay = Duration.zero,
  }) : offset = const Offset(0, .5);

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(begin: widget.offset, end: Offset.zero)
        .animate(curve);
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _opacity,
        child: SlideTransition(position: _offset, child: widget.child),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV BAR
// ─────────────────────────────────────────────────────────────────────────────
class _NavBar extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onFeatures;
  final VoidCallback onPricing;
  final VoidCallback onDocs;
  const _NavBar({
    required this.onLogin,
    required this.onFeatures,
    required this.onPricing,
    required this.onDocs,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 1024;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 16 : 64,
        vertical: isCompact ? 12 : 16,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 22,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: _glassDecoration(fillOpacity: .6, radius: 16),
            child: Row(
              children: [
                _BrandMark(size: isCompact ? 56 : 66),
                const SizedBox(width: 12),
                const _Wordmark(),
                const Spacer(),
                if (!isCompact) ...[
                  _NavButton('Features', onFeatures),
                  _NavButton('Pricing', onPricing),
                  _NavButton('Docs', onDocs),
                  const SizedBox(width: 18),
                ],
                _PrimaryButton(
                  onPressed: onLogin,
                  icon: Icons.login_rounded,
                  label: 'Log In',
                  compact: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'TЯAKR',
      style: TextStyle(
        color: _text,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO
// ─────────────────────────────────────────────────────────────────────────────
class _HeroSection extends StatelessWidget {
  final VoidCallback onStartTrial;
  final VoidCallback onBookDemo;
  const _HeroSection({
    required this.onStartTrial,
    required this.onBookDemo,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 980;
    final copy = Column(
      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        const _Reveal(
          child: _Eyebrow(
            icon: Icons.bolt_rounded,
            text: 'WORKFORCE MANAGEMENT',
          ),
        ),
        const SizedBox(height: 24),
        _Reveal(
          delay: const Duration(milliseconds: 110),
          child: _HeroTitle(compact: compact),
        ),
        const SizedBox(height: 22),
        _Reveal(
          delay: const Duration(milliseconds: 220),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              'Attendance, QR check-in, geo-tagging, leave, and payroll — unified in one secure, role-based workspace your whole organization can trust.',
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: _text2,
                fontSize: compact ? 17 : 19,
                height: 1.55,
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        _Reveal(
          delay: const Duration(milliseconds: 330),
          child: Wrap(
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            spacing: 16,
            runSpacing: 14,
            children: [
              _PrimaryButton(
                onPressed: onStartTrial,
                icon: Icons.rocket_launch_rounded,
                label: 'Start Free Trial',
              ),
              _SecondaryButton(
                onPressed: onBookDemo,
                icon: Icons.calendar_month_rounded,
                label: 'Book a Demo',
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        _Reveal(
          delay: const Duration(milliseconds: 440),
          child: _TrustLine(),
        ),
      ],
    );

    const visual = _Reveal(
      delay: Duration(milliseconds: 280),
      child: _HeroVisual(),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          compact ? 20 : 72, 28, compact ? 20 : 72, 60),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: compact
            ? Column(children: [copy, const SizedBox(height: 44), visual])
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 11, child: copy),
                  const SizedBox(width: 56),
                  const Expanded(flex: 10, child: visual),
                ],
              ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Eyebrow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFF97316).withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFF97316), size: 16),
          const SizedBox(width: 8),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (b) => _warmGradient.createShader(b),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTitle extends StatelessWidget {
  final bool compact;
  const _HeroTitle({required this.compact});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => _warmGradient.createShader(bounds),
      child: Text(
        'The modern command center\nfor attendance & HR',
        textAlign: compact ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontSize: compact ? 38 : 58,
          height: 1.05,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
        ),
      ),
    );
  }
}

class _TrustLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.verified_user_rounded, 'Secure QR access'),
      (Icons.insights_rounded, 'Live dashboards'),
      (Icons.groups_rounded, '3 role tiers'),
    ];
    return Wrap(
      spacing: 22,
      runSpacing: 10,
      children: [
        for (final (icon, label) in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _accentBright, size: 17),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(color: _muted, fontSize: 13.5)),
            ],
          ),
      ],
    );
  }
}

// Hero visual: a browser-window-framed product mockup + floating glass chips.
class _HeroVisual extends StatelessWidget {
  const _HeroVisual();
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final target = compact ? 360.0 : 540.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth
            ? constraints.maxWidth.clamp(240.0, target)
            : target;
        return SizedBox(
      width: w,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: _Glow(color: _accent.withValues(alpha: .22), size: 360),
          ),
          _BrowserFrame(height: compact ? 380 : 390, child: const _DashboardMockup()),
          Positioned(
            right: compact ? -6 : 18,
            top: compact ? -10 : 4,
            child: const _FloatingChip(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Check-in verified',
              caption: 'QR · geo · time',
            ),
          ),
          Positioned(
            left: compact ? -6 : -12,
            bottom: compact ? 16 : 30,
            child: const _FloatingChip(
              icon: Icons.insights_rounded,
              title: 'Report ready',
              caption: 'monthly analytics',
              accent: _accentBright,
            ),
          ),
        ],
      ),
        );
      },
    );
  }
}

class _BrowserFrame extends StatelessWidget {
  final Widget child;
  final double? height;
  const _BrowserFrame({required this.child, this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border.withValues(alpha: .5)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: .25),
            blurRadius: 50,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // window chrome
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _surfaceRaised.withValues(alpha: .7),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: _border.withValues(alpha: .4)),
              ),
            ),
            child: Row(
              children: [
                for (final c in [Colors.red, Colors.amber, Colors.green])
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.withValues(alpha: .8),
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 22,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: _bg.withValues(alpha: .6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'app.trakr.example.com/dashboard',
                      style: TextStyle(color: _muted, fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)), child: child)),
        ],
      ),
    );
  }
}

// Lightweight, in-Flutter "product screenshot" mockup (no heavy images).
class _DashboardMockup extends StatelessWidget {
  const _DashboardMockup();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Team Attendance',
                  style: TextStyle(
                      color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Today',
                    style: TextStyle(color: _accentBright, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Row(
            children: [
              _MiniStat('Present', '92%', _accentBright),
              SizedBox(width: 10),
              _MiniStat('Late', '5', _secondary),
              SizedBox(width: 10),
              _MiniStat('Absent', '3', Colors.redAccent),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Weekly trend',
              style: TextStyle(color: _text2, fontSize: 12)),
          const SizedBox(height: 10),
          const _MiniBars(),
          const SizedBox(height: 16),
          const _MiniRow(
              icon: Icons.check_circle_rounded, label: 'A. Sharma checked in', time: '09:02'),
          const SizedBox(height: 8),
          const _MiniRow(
              icon: Icons.access_time_rounded, label: 'R. Verma late by 12m', time: '09:18'),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: _glassDecoration(fillOpacity: .4, radius: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars();
  static const _h = [.55, .7, .62, .85, .74, .95, .8];
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < _h.length; i++)
          Expanded(
            child: Container(
              height: 60 * _h[i],
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_accent, _accentBright],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String time;
  const _MiniRow(
      {required this.icon, required this.label, required this.time});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _glassDecoration(fillOpacity: .3, radius: 10),
      child: Row(
        children: [
          Icon(icon, color: _accentBright, size: 16),
          const SizedBox(width: 9),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: _text2, fontSize: 12))),
          Text(time, style: const TextStyle(color: _muted, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _FloatingChip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;
  final Color accent;
  const _FloatingChip({
    required this.icon,
    required this.title,
    required this.caption,
    this.accent = _accentAlt,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 178,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .25),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
                Text(caption,
                    style: const TextStyle(color: _muted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TRUSTED BY STRIP
// ─────────────────────────────────────────────────────────────────────────────
class _TrustedByStrip extends StatelessWidget {
  const _TrustedByStrip();
  @override
  Widget build(BuildContext context) {
    // PLACEHOLDER LOGOS — replace with real customer/partner logos before launch.
    const names = ['NORTHWIND', 'ACME CORP', 'GLOBEX', 'INITECH', 'UMBRELLA', 'Hooli'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: _Reveal(
        child: Column(
          children: [
            const Text(
              'TRUSTED BY MODERN TEAMS',
              style: TextStyle(
                color: _muted, fontSize: 12.5, letterSpacing: 2, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 34,
              runSpacing: 18,
              children: [
                for (final n in names)
                  Text(n,
                      style: TextStyle(
                        color: _text2.withValues(alpha: .7),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION SHELL
// ─────────────────────────────────────────────────────────────────────────────
class _SectionShell extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;
  const _SectionShell({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 72, vertical: compact ? 40 : 64),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Column(
          children: [
            _Reveal(
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: const Color(0xFFF97316).withValues(alpha: .3)),
                    ),
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (b) => _warmGradient.createShader(b),
                      child: Text(eyebrow.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          )),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: compact ? 26 : 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _text2, fontSize: compact ? 15 : 17, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            child,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FEATURE GRID (6 features)
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureSection extends StatelessWidget {
  const _FeatureSection({super.key});
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final features = [
      const _Feature(Icons.qr_code_2_rounded, 'QR Attendance',
          'Employees scan the assigned QR to check in and out in seconds — no manual registers.', _accentAlt),
      const _Feature(Icons.location_on_rounded, 'Geo-Tagging',
          'Validate attendance against configured office locations with smart geo-fencing.', _accentBright),
      const _Feature(Icons.event_available_rounded, 'Leave & Permissions',
          'Request leave, late entry, and step-out permissions from one clean portal.', _secondary),
      const _Feature(Icons.admin_panel_settings_rounded, 'Role-Based Access',
          'Separate, secure dashboards for staff, managers, and administrators.', _accent),
      const _Feature(Icons.analytics_rounded, 'Monthly Analytics',
          'Trend attendance, late patterns, and utilization with exportable reports.', _accentBright),
      const _Feature(Icons.payments_rounded, 'Payroll Ready',
          'Attendance feeds salary calculations — accurate, auditable, and on time.', _accentAlt),
    ];
    return _SectionShell(
      eyebrow: 'Features',
      title: 'Everything your attendance team needs',
      subtitle:
          'Built for repeated daily use by staff, managers, and administrators — secure by default, delightful to operate.',
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: compact ? 1 : 3,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: 1.25,
        ),
        itemCount: features.length,
        itemBuilder: (_, i) => _Reveal(
          delay: Duration(milliseconds: 60 * i),
          child: _FeatureCard(features[i]),
        ),
      ),
    );
  }
}

class _Feature {
  final IconData icon;
  final String title;
  final String body;
  final Color accent;
  const _Feature(this.icon, this.title, this.body, this.accent);
}

class _FeatureCard extends StatelessWidget {
  final _Feature f;
  const _FeatureCard(this.f);
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: f.accent.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(f.icon, color: f.accent, size: 24),
          ),
          const SizedBox(height: 18),
          Text(f.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Expanded(
            child: Text(f.body,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _text2, fontSize: 14.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRODUCT SHOWCASE (browser frame + annotated callouts)
// ─────────────────────────────────────────────────────────────────────────────
class _ProductShowcaseSection extends StatelessWidget {
  const _ProductShowcaseSection({super.key});
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return _SectionShell(
      eyebrow: 'Product',
      title: 'One view across your whole workforce',
      subtitle:
          'From live check-ins to monthly analysis — TRAKR turns scattered registers into a single source of truth.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!compact) ...[
            Expanded(
              flex: 7,
              child: _Reveal(
                child: _BrowserFrame(
                  height: 420,
                  child: Image.asset(
                    'assets/scan2.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 36),
          ],
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment:
                  compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                const _Callout(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'QR + geo verification',
                  body: 'Every scan is bound to time, role, and location rules.',
                ),
                const SizedBox(height: 16),
                const _Callout(
                  icon: Icons.insights_rounded,
                  title: 'Manager dashboards',
                  body: 'See who is in, who is late, and who needs approval.',
                ),
                const SizedBox(height: 16),
                const _Callout(
                  icon: Icons.download_rounded,
                  title: 'Exports & payroll',
                  body: 'CSV, Excel, and PDF reports ready for payroll.',
                ),
                if (compact) ...[
                  const SizedBox(height: 24),
                  _Reveal(
                    child: _BrowserFrame(
                      height: 320,
                      child: Image.asset('assets/scan2.png',
                          fit: BoxFit.cover, filterQuality: FilterQuality.high),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _Callout(
      {required this.icon, required this.title, required this.body});
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accentBright, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: _text, fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body,
                    style: const TextStyle(color: _text2, fontSize: 13.5, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOW IT WORKS (3 steps)
// ─────────────────────────────────────────────────────────────────────────────
class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection();
  static const _steps = [
    (Icons.person_add_alt_1_rounded, 'Onboard your team',
        'Admins create staff profiles and role-scoped login access.'),
    (Icons.qr_code_scanner_rounded, 'Capture attendance',
        'Staff scan QR, with time, role, and location rules enforced.'),
    (Icons.analytics_rounded, 'Review & report',
        'Managers see live logs; admins export monthly analytics.'),
  ];
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return _SectionShell(
      eyebrow: 'How it works',
      title: 'Live in three simple steps',
      subtitle: 'TЯAKR keeps the daily workflow simple so teams focus on work.',
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            Expanded(
              child: _Reveal(
                delay: Duration(milliseconds: 90 * i),
                child: _StepCard(i, _steps[i]),
              ),
            ),
            if (!compact && i != _steps.length - 1)
              const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final (IconData, String, String) step;
  const _StepCard(this.index, this.step);
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppThemeColors.actionGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${index + 1}',
                style: const TextStyle(
                    color: _onAccent, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 16),
          Text(step.$2,
              style: const TextStyle(color: _text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(step.$3,
              style: const TextStyle(color: _text2, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATS BAND
// ─────────────────────────────────────────────────────────────────────────────
class _StatsBand extends StatelessWidget {
  const _StatsBand({super.key});
  // PLACEHOLDER STATS — replace with verified figures before launch.
  static const _stats = [
    ('99.9%', 'Uptime SLA'),
    ('500+', 'Teams onboarded'),
    ('2.4M', 'Check-ins tracked'),
    ('4.9/5', 'Avg. customer rating'),
  ];
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 72, vertical: 40),
      child: _Reveal(
        child: _GlassCard(
          fillOpacity: .55,
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
          child: compact
              ? Column(
                  children: [
                    for (final s in _stats) ...[
                      _StatItem(s.$1, s.$2),
                      if (s != _stats.last) const SizedBox(height: 22),
                    ],
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final s in _stats) _StatItem(s.$1, s.$2),
                  ],
                ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem(this.value, this.label);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => _warmGradient.createShader(bounds),
          child: Text(value,
              style: const TextStyle(
                  fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1)),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: _text2, fontSize: 14)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTIMONIALS
// ─────────────────────────────────────────────────────────────────────────────
class _TestimonialsSection extends StatelessWidget {
  const _TestimonialsSection({super.key});
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    // PLACEHOLDER TESTIMONIALS — replace with real customer quotes before launch.
    const quotes = [
      ('“TЯAKR replaced three spreadsheets and a WhatsApp group. Check-ins are effortless.”',
          'Priya N.', 'HR Lead, Northwind'),
      ('“The monthly analytics alone saved us days of payroll reconciliation.”',
          'Marcus L.', 'Operations, Globex'),
      ('“Role-based access means managers see exactly what they need — nothing more.”',
          'Sofia R.', 'Admin, Initech'),
    ];
    return _SectionShell(
      eyebrow: 'Testimonials',
      title: 'Loved by operations teams',
      subtitle: 'Real outcomes from organizations running TRAKR daily.',
      child: Row(
        children: [
          for (var i = 0; i < quotes.length; i++) ...[
            Expanded(
              child: _Reveal(
                delay: Duration(milliseconds: 90 * i),
                child: _TestimonialCard(quotes[i].$1, quotes[i].$2, quotes[i].$3),
              ),
            ),
            if (!compact && i != quotes.length - 1)
              const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  final String quote;
  final String name;
  final String role;
  const _TestimonialCard(this.quote, this.name, this.role);
  @override
  Widget build(BuildContext context) {
    return _GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote_rounded, color: _accent.withValues(alpha: .6), size: 32),
          const SizedBox(height: 10),
          Text(quote,
              style: const TextStyle(color: _text, fontSize: 15.5, height: 1.55)),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _accent.withValues(alpha: .2),
                child: Text(name[0],
                    style: const TextStyle(color: _accentBright, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(role, style: const TextStyle(color: _muted, fontSize: 12.5)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PRICING
// ─────────────────────────────────────────────────────────────────────────────
class _PricingSection extends StatelessWidget {
  const _PricingSection({super.key});
  // PLACEHOLDER PRICING — replace with real plans/prices before launch.
  static const _plans = [
    ('Starter', 'Free', ['QR attendance', 'Up to 25 staff', 'Basic reports'], false),
    ('Growth', '\$4', ['Unlimited staff', 'Geo-tagging', 'Monthly analytics', 'Payroll export'], true),
    ('Enterprise', 'Custom', ['SSO & audit logs', 'Dedicated support', 'Custom roles'], false),
  ];
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return _SectionShell(
      eyebrow: 'Pricing',
      title: 'Simple, transparent plans',
      subtitle: 'Start free. Upgrade as your team grows. Cancel anytime.',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _plans.length; i++) ...[
            Expanded(
              child: _Reveal(
                delay: Duration(milliseconds: 90 * i),
                child: _PlanCard(_plans[i]),
              ),
            ),
            if (!compact && i != _plans.length - 1)
              const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final (String, String, List<String>, bool) plan;
  const _PlanCard(this.plan);
  @override
  Widget build(BuildContext context) {
    final featured = plan.$4;
    return Container(
      decoration: _glassDecoration(
        fillOpacity: featured ? .7 : .45,
        borderColor: featured ? const Color(0xFFF97316) : _border,
        borderOpacity: featured ? .55 : .22,
        radius: 18,
      ),
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (featured)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: .15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('MOST POPULAR',
                  style: TextStyle(color: Color(0xFFF97316), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
          Text(plan.$1, style: const TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(plan.$2,
                  style: const TextStyle(
                      color: _text, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
              if (plan.$2 == '\$4')
                const Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 4),
                  child: Text('/user/mo', style: TextStyle(color: _muted, fontSize: 13)),
                ),
            ],
          ),
          const SizedBox(height: 18),
          for (final f in plan.$3)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: _accentBright, size: 17),
                  const SizedBox(width: 9),
                  Expanded(child: Text(f, style: const TextStyle(color: _text2, fontSize: 14))),
                ],
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: featured
                ? _PrimaryButton(onPressed: () {}, label: 'Start Free Trial')
                : _SecondaryButton(onPressed: () {}, label: 'Choose ${plan.$1}'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEMO CTA BAND
// ─────────────────────────────────────────────────────────────────────────────
class _DemoCtaBand extends StatelessWidget {
  final VoidCallback onStartTrial;
  const _DemoCtaBand({super.key, required this.onStartTrial});
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 72, vertical: 40),
      child: _Reveal(
        child: Stack(
          children: [
            Positioned.fill(
              child: _Glow(color: _accent.withValues(alpha: .25), size: 380),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 24 : 56, vertical: compact ? 36 : 56),
              decoration: BoxDecoration(
                gradient: AppThemeColors.actionGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: .35),
                    blurRadius: 50,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: compact
                  ? Column(
                      children: [
                        const _CtaCopy(),
                        const SizedBox(height: 24),
                        _CtaButtons(onStartTrial: onStartTrial),
                      ],
                    )
                  : Row(
                      children: [
                        const Expanded(child: _CtaCopy()),
                        const SizedBox(width: 32),
                        _CtaButtons(onStartTrial: onStartTrial),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaCopy extends StatelessWidget {
  const _CtaCopy();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ready to modernize attendance?',
            style: TextStyle(
                color: _onAccent, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.5)),
        const SizedBox(height: 10),
        Text('Book a personalized demo or start your free trial — no credit card required.',
            style: TextStyle(color: _onAccent.withValues(alpha: .85), fontSize: 16, height: 1.5)),
      ],
    );
  }
}

class _CtaButtons extends StatelessWidget {
  final VoidCallback onStartTrial;
  const _CtaButtons({required this.onStartTrial});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PrimaryButton(onPressed: onStartTrial, label: 'Start Free Trial'),
        const SizedBox(width: 14),
        OutlinedButton(
          onPressed: () {},
          style: OutlinedButton.styleFrom(
            foregroundColor: _onAccent,
            side: BorderSide(color: _onAccent.withValues(alpha: .6)),
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Book a Demo',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FOOTER
// ─────────────────────────────────────────────────────────────────────────────
class _SiteFooter extends StatelessWidget {
  const _SiteFooter();
  static const _youtube = 'https://www.youtube.com/@CloudMaSa_Technologies';
  static const _facebook =
      'https://www.facebook.com/people/CloudMasa-T/pfbid0W1cEry6U655S56vUrQAXsqH6fb3NYqn3YD6aedZAANbiVrXkjumyqPLWVQzgBDNel/';
  static const _instagram = 'https://www.instagram.com/cloudmasa_technology/';
  static const _github = 'https://github.com/CloudMasa-Tech';

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(compact ? 22 : 64, 56, compact ? 22 : 64, 40),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _border.withValues(alpha: .4))),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: compact
            ? const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FooterBrand(),
                  SizedBox(height: 36),
                  _FooterLinks(),
                ],
              )
            : const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _FooterBrand()),
                  SizedBox(width: 48),
                  Expanded(flex: 3, child: _FooterLinks()),
                ],
              ),
      ),
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            TrakrLogo(size: 52),
            SizedBox(width: 10),
            Text('TЯAKR',
                style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ],
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: const Text(
            'Smart attendance and workforce tracking for modern organizations. Secure, simple, and fully digital.',
            style: TextStyle(color: _text2, fontSize: 15, height: 1.6),
          ),
        ),
        const SizedBox(height: 22),
        _SocialBar(
          onYoutube: () => _openExternal(_SiteFooter._youtube),
          onInstagram: () => _openExternal(_SiteFooter._instagram),
          onFacebook: () => _openExternal(_SiteFooter._facebook),
          onGithub: () => _openExternal(_SiteFooter._github),
        ),
      ],
    );
  }
}

class _SocialBar extends StatelessWidget {
  final VoidCallback onYoutube;
  final VoidCallback onInstagram;
  final VoidCallback onFacebook;
  final VoidCallback onGithub;
  const _SocialBar({
    required this.onYoutube,
    required this.onInstagram,
    required this.onFacebook,
    required this.onGithub,
  });
  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.play_arrow_rounded, onYoutube),
      (Icons.camera_alt_rounded, onInstagram),
      (Icons.facebook_rounded, onFacebook),
      (Icons.code_rounded, onGithub),
    ];
    return Row(
      children: [
        for (final (icon, onTap) in items)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 40,
                height: 40,
                decoration: _glassDecoration(fillOpacity: .4, radius: 10),
                child: Icon(icon, color: _text2, size: 19),
              ),
            ),
          ),
      ],
    );
  }
}

class _FooterLinks extends StatelessWidget {
  const _FooterLinks();
  @override
  Widget build(BuildContext context) {
    const columns = [
      ('PRODUCT', ['QR Attendance', 'Geo-Tagging', 'Leave Management', 'Analytics', 'Payroll']),
      ('RESOURCES', ['Documentation', 'How It Works', 'Help Center', 'Security']),
      ('COMPANY', ['About Us', 'Pricing', 'Privacy Policy', 'Terms of Service']),
    ];
    final compact = MediaQuery.sizeOf(context).width < 620;
    if (compact) {
      return Column(
        children: [
          for (final c in columns) ...[
            _FooterColumn(c.$1, c.$2),
            const SizedBox(height: 28),
          ],
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in columns) Expanded(child: _FooterColumn(c.$1, c.$2)),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  final String title;
  final List<String> items;
  const _FooterColumn(this.title, this.items);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(color: _secondary, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 18),
        for (final item in items) ...[
          Text(item, style: const TextStyle(color: _text2, fontSize: 14.5)),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}
