import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/login_screen.dart';
import '../../widgets/common/trakr_logo.dart';

const _landingBackground = Color(0xFF050A14);
const _landingDarkCard = Color(0xFF0D1624);
const _landingPanel = Color(0xFF111D2C);
const _landingBlue = Color(0xFF2F8CFF);
const _landingCyan = Color(0xFF35E9D0);
const _landingPink = Color(0xFFFF4FB3);
const _landingOrange = Color(0xFFFFB85C);
const _landingWhite = Color(0xFFEAF3FF);
const _landingMuted = Color(0xFF9AA8B9);

// Fixed-brand landing/marketing palette. This page is an always-dark showcase
// (shown pre-auth on web), so its colors are centralized constants rather than
// theme tokens — widgets in this file reference names, never literals.
const _landingOverlay = Color(0xFFFFFFFF);
const _landingShadow = Color(0xFF000000);
const _landingShadowMid = Color(0x66000000);
const _landingShadowDark = Color(0x88000000);
const _landingNavyGlass = Color(0xFF07101D);
const _landingNavyGlass2 = Color(0xFF091322);
const _landingNavyGlass3 = Color(0xFF071326);
const _landingDeepNavy = Color(0xFF020817);
const _landingGradientBlue = Color(0xFF009DFF);
const _landingGradientBlueDeep = Color(0xFF005CFF);
const _landingGlowBlueSoft = Color(0x4000AEFF);
const _landingGlowBlueFaint = Color(0x1800AEFF);
const _landingGlowBlueDeep = Color(0x55116AFF);
const _landingCardBlueA = Color(0xFF3F8DFF);
const _landingCardBlueB = Color(0xFF115DFF);
const _landingCardBlueC = Color(0xFF4AA2FF);
const _landingCardBlueD = Color(0xFF1C62FF);
const _landingCardBlueE = Color(0xFF2787FF);
const _landingCardBlueF = Color(0xFF1259D8);
const _landingCardBlueG = Color(0xFF168BFF);
const _landingCardBlueH = Color(0xFF005F9F);
const _landingFeatureGold = Color(0xFFFFC04D);
const _landingFeaturePink = Color(0xFFFF4C8E);
const _landingFeaturePurple = Color(0xFF7A4DFF);
const _landingFeatureSlate = Color(0xFF7F91A8);
const _landingFeatureSlateDeep = Color(0xFF1B2738);
const _landingStatPink = Color(0xFFFF5C93);
const _landingStatPurple = Color(0xFF8B6DFF);
const _landingStatGreen = Color(0xFF3AF0A0);
const _landingSubtext = Color(0xFFB7C2D4);
const _landingFooterBg = Color(0xFF031126);
const _landingFooterBg2 = Color(0xFF061A38);
const _landingFooterBg3 = Color(0xFF021224);
const _landingFooterBg4 = Color(0xFF041F3D);

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
  final _useKey = GlobalKey();
  final _worksKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _contactKey = GlobalKey();
  late final AnimationController _backdropController;

  @override
  void initState() {
    super.initState();
    _backdropController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  @override
  void dispose() {
    _backdropController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTheme = Theme.of(context);
    return Theme(
      data: currentTheme.copyWith(
        scaffoldBackgroundColor: _landingBackground,
        textTheme: GoogleFonts.interTextTheme(currentTheme.textTheme).apply(
          bodyColor: _landingWhite,
          displayColor: _landingWhite,
        ),
      ),
      child: Scaffold(
        backgroundColor: _landingBackground,
        body: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _NetworkBackdropPainter(_backdropController),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    const SizedBox(height: 104),
                    _HeroSection(
                      onLogin: _goToLogin,
                      onScanFlow: () => _scrollTo(_useKey),
                    ),
                    const _ProductShowcaseSection(),
                    _FeatureSection(key: _featuresKey),
                    _UseSection(key: _useKey),
                    _HowItWorksSection(key: _worksKey),
                    const _WhyUsefulSection(),
                    _CompanySection(key: _aboutKey),
                    _SocialFooter(key: _contactKey),
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
                onUse: () => _scrollTo(_useKey),
                onWorks: () => _scrollTo(_worksKey),
                onAbout: () => _scrollTo(_aboutKey),
                onContact: () => _scrollTo(_contactKey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onFeatures;
  final VoidCallback onUse;
  final VoidCallback onWorks;
  final VoidCallback onAbout;
  final VoidCallback onContact;

  const _NavBar({
    required this.onLogin,
    required this.onFeatures,
    required this.onUse,
    required this.onWorks,
    required this.onAbout,
    required this.onContact,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 1080;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 18 : 72,
        vertical: isCompact ? 14 : 18,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 16 : 22,
              vertical: isCompact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: _landingNavyGlass.withValues(alpha: .78),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _landingOverlay.withValues(alpha: .09)),
            ),
            child: Row(
              children: [
                _BrandMark(size: isCompact ? 64 : 76),
                const Spacer(),
                if (!isCompact) ...[
                  _NavButton('Features', onFeatures),
                  _NavButton('How to Use It', onUse),
                  _NavButton('How It Works', onWorks),
                  _NavButton('About Us', onAbout),
                  _NavButton('Contact', onContact),
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

class _PrimaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool compact;

  const _PrimaryButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_landingGradientBlue, _landingGradientBlueDeep],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _landingGradientBlue.withValues(alpha: .40),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 22 : 28,
              vertical: compact ? 15 : 18,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: compact ? 18 : 21, color: _landingWhite),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: _landingWhite,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;

  const _SecondaryButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 18),
          decoration: BoxDecoration(
            color: _landingOverlay.withValues(alpha: .04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _landingOverlay.withValues(alpha: .10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _landingWhite),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: _landingWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
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
    final color = _hovered ? _landingBlue : _landingMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: TextButton(
        onPressed: widget.onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 160),
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
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
    _opacity = Tween<double>(begin: .86, end: 1).animate(
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
          boxShadow: const [
            BoxShadow(
              color: _landingGlowBlueSoft,
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.size * .22),
          child: TrakrLogo(
            size: widget.size,
          ),
        ),
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final VoidCallback onLogin;
  final VoidCallback onScanFlow;

  const _HeroSection({
    required this.onLogin,
    required this.onScanFlow,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 940;
    final copy = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        const _BottomToTopReveal(
          delay: Duration(milliseconds: 120),
          child: _HeroBadge(),
        ),
        const SizedBox(height: 26),
        _BottomToTopReveal(
          delay: const Duration(milliseconds: 260),
          child: _AnimatedHeroTitle(
            compact: compact,
            prefix: 'QR attendance that ',
            highlight: 'scans fast.',
            suffix: '\nTracks clean.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
          ),
        ),
        const SizedBox(height: 24),
        _BottomToTopReveal(
          delay: const Duration(milliseconds: 420),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'TЯAKR gives every team a secure scan flow, live attendance records, leave approvals, permissions, reports, and manager visibility from one polished web portal.',
              textAlign: compact ? TextAlign.center : TextAlign.start,
              style: const TextStyle(
                color: _landingMuted,
                fontSize: 19,
                height: 1.5,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        const SizedBox(height: 34),
        _BottomToTopReveal(
          delay: const Duration(milliseconds: 560),
          child: Wrap(
            alignment: compact ? WrapAlignment.center : WrapAlignment.start,
            spacing: 16,
            runSpacing: 14,
            children: [
              _PrimaryButton(
                onPressed: onLogin,
                icon: Icons.arrow_forward_rounded,
                label: 'Open Web Login',
              ),
              _SecondaryButton(
                onPressed: onScanFlow,
                icon: Icons.qr_code_scanner_rounded,
                label: 'See Scan Flow',
              ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        const _BottomToTopReveal(
          delay: Duration(milliseconds: 700),
          child: _HeroStatsStrip(),
        ),
      ],
    );
    const showcase = _BottomToTopReveal(
      delay: Duration(milliseconds: 620),
      child: _ScannerShowcase(),
    );

    return Padding(
      padding:
          EdgeInsets.fromLTRB(compact ? 22 : 80, 34, compact ? 22 : 80, 68),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: compact
            ? Column(
                children: [
                  copy,
                  const SizedBox(height: 44),
                  showcase,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 11, child: copy),
                  const SizedBox(width: 56),
                  const Expanded(flex: 10, child: showcase),
                ],
              ),
      ),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _landingCyan.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _landingCyan.withValues(alpha: .35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, color: _landingCyan, size: 18),
          SizedBox(width: 8),
          Text(
            'LIVE QR ATTENDANCE PORTAL',
            style: TextStyle(
              color: _landingCyan,
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroStatsStrip extends StatelessWidget {
  const _HeroStatsStrip();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _HeroStat(Icons.verified_user_rounded, 'Secure QR', 'scan access'),
        _HeroStat(Icons.schedule_rounded, 'Live Logs', 'instant records'),
        _HeroStat(
            Icons.people_alt_rounded, '3 Roles', 'admin / manager / staff'),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _HeroStat(this.icon, this.title, this.caption);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _landingOverlay.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _landingOverlay.withValues(alpha: .08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _landingCyan, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _landingWhite,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _landingMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerShowcase extends StatelessWidget {
  const _ScannerShowcase();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return SizedBox(
      width: compact ? 360 : 520,
      height: compact ? 520 : 650,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: RadialGradient(
                  center: const Alignment(.12, -.18),
                  radius: .92,
                  colors: [
                    _landingBlue.withValues(alpha: .30),
                    _landingCyan.withValues(alpha: .12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: compact ? 4 : 26,
            top: compact ? 0 : 8,
            child: Transform.rotate(
              angle: compact ? .02 : .045,
              child: Image.asset(
                'assets/scan1.png',
                width: compact ? 286 : 420,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
          Positioned(
            left: compact ? 0 : -10,
            bottom: compact ? 24 : 42,
            child: Transform.rotate(
              angle: -.065,
              child: Container(
                width: compact ? 180 : 238,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _landingPanel.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _landingOverlay.withValues(alpha: .08)),
                  boxShadow: const [
                    BoxShadow(
                      color: _landingShadowMid,
                      blurRadius: 30,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/scan.png',
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: compact ? 24 : 34,
            top: compact ? 38 : 58,
            child: const _FloatingSignalCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan verified',
              caption: 'QR + time + role',
            ),
          ),
          Positioned(
            right: compact ? 0 : 18,
            bottom: compact ? 0 : 18,
            child: const _FloatingSignalCard(
              icon: Icons.insights_rounded,
              title: 'Report ready',
              caption: 'live dashboard',
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingSignalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String caption;

  const _FloatingSignalCard({
    required this.icon,
    required this.title,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 174,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _landingNavyGlass2.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _landingBlue.withValues(alpha: .28)),
        boxShadow: const [
          BoxShadow(
            color: _landingGlowBlueDeep,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _landingCyan, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _landingWhite,
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _landingMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomToTopReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;

  const _BottomToTopReveal({
    required this.child,
    this.delay = Duration.zero,
  });

  @override
  State<_BottomToTopReveal> createState() => _BottomToTopRevealState();
}

class _BottomToTopRevealState extends State<_BottomToTopReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _offset = Tween<Offset>(
      begin: const Offset(0, .55),
      end: Offset.zero,
    ).animate(curve);
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
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: widget.child,
      ),
    );
  }
}

class _AnimatedHeroTitle extends StatefulWidget {
  final bool compact;
  final String prefix;
  final String highlight;
  final String suffix;
  final TextAlign textAlign;

  const _AnimatedHeroTitle({
    required this.compact,
    required this.prefix,
    required this.highlight,
    this.suffix = '',
    this.textAlign = TextAlign.center,
  });

  @override
  State<_AnimatedHeroTitle> createState() => _AnimatedHeroTitleState();
}

class _AnimatedHeroTitleState extends State<_AnimatedHeroTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: _landingWhite,
      fontFamily: 'Poppins',
      fontSize: widget.compact ? 40 : 58,
      height: 1.1,
      fontWeight: FontWeight.w700,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final glow = .45 + math.sin(_controller.value * math.pi) * .55;
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: widget.prefix),
              TextSpan(
                text: widget.highlight,
                style: TextStyle(
                  color: Color.lerp(
                    _landingBlue,
                    _landingPink,
                    glow,
                  ),
                  shadows: [
                    Shadow(
                      color: _landingBlue.withValues(
                        alpha: .18 + (.32 * glow),
                      ),
                      blurRadius: 14 + (12 * glow),
                    ),
                  ],
                ),
              ),
              TextSpan(text: widget.suffix),
            ],
          ),
          textAlign: widget.textAlign,
          style: baseStyle,
        );
      },
    );
  }
}

class _ProductShowcaseSection extends StatelessWidget {
  const _ProductShowcaseSection();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 80,
        compact ? 24 : 34,
        compact ? 22 : 80,
        compact ? 46 : 70,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1260),
        child: Column(
          children: [
            const _BottomToTopReveal(
              delay: Duration(milliseconds: 120),
              child: _ShowcaseHeader(),
            ),
            const SizedBox(height: 28),
            _BottomToTopReveal(
              delay: const Duration(milliseconds: 260),
              child: Container(
                padding: EdgeInsets.all(compact ? 8 : 12),
                decoration: BoxDecoration(
                  color: _landingPanel.withValues(alpha: .70),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: _landingBlue.withValues(alpha: .18)),
                  boxShadow: [
                    BoxShadow(
                      color: _landingBlue.withValues(alpha: .20),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                    ),
                    BoxShadow(
                      color: _landingCyan.withValues(alpha: .10),
                      blurRadius: 54,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/scan2.png',
                    width: double.infinity,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseHeader extends StatelessWidget {
  const _ShowcaseHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Text(
          'PRODUCT PREVIEW',
          style: TextStyle(
            color: _landingCyan,
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Smart attendance, location checks, and QR flow in one view',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _landingWhite,
            fontFamily: 'Poppins',
            fontSize: 34,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FeatureSection extends StatelessWidget {
  const _FeatureSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'FEATURES',
      title: 'Everything your attendance team needs',
      subtitle:
          'Designed for repeated daily use by staff, managers, and administrators.',
      child: _MarqueeCards(
        onCardTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
        children: const [
          _InfoCard(Icons.qr_code_2_rounded, 'QR Attendance',
              'Employees scan the assigned QR to check in and check out quickly.'),
          _InfoCard(Icons.map_rounded, 'Geo Verification',
              'Attendance can be checked against configured work locations.'),
          _InfoCard(Icons.event_available_rounded, 'Leave & Permission',
              'Staff request leave, late entry, and permissions from one portal.'),
          _InfoCard(Icons.notifications_rounded, 'Smart Notifications',
              'Managers and admins receive important attendance alerts instantly.'),
          _InfoCard(Icons.admin_panel_settings_rounded, 'Role Dashboards',
              'Separate views for staff, managers, and admin operations.'),
        ],
      ),
    );
  }
}

class _UseSection extends StatelessWidget {
  const _UseSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const _SectionShell(
      eyebrow: 'HOW TO USE IT',
      title: 'Start attendance in a few simple steps',
      subtitle:
          'TЯAKR keeps the daily workflow simple so teams can focus on work, not paperwork.',
      child: _ScanWorkflowPanel(),
    );
  }
}

class _HowItWorksSection extends StatelessWidget {
  const _HowItWorksSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'HOW IT WORKS',
      title: 'A transparent digital attendance path',
      subtitle:
          'Every action creates traceable data that managers can review in real time.',
      child: _StaticCards(
        onCardTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
        children: const [
          _TimelineCard(
            index: 1,
            item: _TimelineItem(Icons.person_add_alt_1_rounded, 'Onboard team',
                'Admin or manager creates staff profiles and login access.'),
          ),
          _TimelineCard(
            index: 2,
            item: _TimelineItem(Icons.security_rounded, 'Verify attendance',
                'QR scans, time windows, and location rules support secure marking.'),
          ),
          _TimelineCard(
            index: 3,
            item: _TimelineItem(Icons.rule_rounded, 'Approve requests',
                'Leave, permission, and missed checkout flows go to the right approver.'),
          ),
          _TimelineCard(
            index: 4,
            item: _TimelineItem(Icons.analytics_rounded, 'Analyze outcomes',
                'Dashboards summarize attendance trends, history, and report data.'),
          ),
        ],
      ),
    );
  }
}

class _WhyUsefulSection extends StatelessWidget {
  const _WhyUsefulSection();

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'WHY THIS IS USEFUL',
      title: 'Less manual work, clearer decisions',
      subtitle:
          'TЯAKR replaces scattered registers and messages with one verified attendance system.',
      child: _MarqueeCards(
        onCardTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        ),
        children: const [
          _InfoCard(Icons.check_circle_outline_rounded, 'Transparent Records',
              'Managers can see who checked in, who is late, and who needs approval.'),
          _InfoCard(Icons.speed_rounded, 'Faster Operations',
              'Daily attendance, requests, and reports move through one workflow.'),
          _InfoCard(Icons.visibility_rounded, 'Admin Visibility',
              'Admins get live logs, history, employee analysis, and exports.'),
          _InfoCard(Icons.people_alt_rounded, 'Employee Friendly',
              'Staff can check attendance status and submit requests without confusion.'),
          _InfoCard(Icons.lock_rounded, 'Secure Access',
              'Role-based dashboards keep each user focused on the right data.'),
        ],
      ),
    );
  }
}

class _ScanWorkflowPanel extends StatelessWidget {
  const _ScanWorkflowPanel();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 840;
        const steps = [
          _WorkflowStep('01', Icons.login_rounded, 'Sign in',
              'Use the assigned staff, manager, or admin account.'),
          _WorkflowStep('02', Icons.qr_code_scanner_rounded, 'Scan QR',
              'Place the code in frame and submit attendance quickly.'),
          _WorkflowStep('03', Icons.fact_check_rounded, 'Verify',
              'Time, role, status, and location rules are stored.'),
          _WorkflowStep('04', Icons.analytics_rounded, 'Review',
              'Managers see logs, approvals, exports, and monthly analysis.'),
        ];

        final stepList = Column(
          children: [
            for (var index = 0; index < steps.length; index++) ...[
              steps[index],
              if (index != steps.length - 1) const SizedBox(height: 12),
            ],
          ],
        );

        final visual = Container(
          height: compact ? 470 : 560,
          decoration: BoxDecoration(
            color: _landingDarkCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _landingOverlay.withValues(alpha: .06)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _PanelGridPainter()),
              ),
              Image.asset(
                'assets/scan.png',
                height: compact ? 420 : 510,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              Positioned(
                right: compact ? 18 : 28,
                top: compact ? 18 : 28,
                child: const _WorkflowBadge('Auto scan', Icons.flash_on),
              ),
              Positioned(
                left: compact ? 18 : 28,
                bottom: compact ? 18 : 28,
                child: const _WorkflowBadge('Record saved', Icons.done),
              ),
            ],
          ),
        );

        if (compact) {
          return Column(
            children: [
              visual,
              const SizedBox(height: 18),
              stepList,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 6, child: stepList),
            const SizedBox(width: 34),
            Expanded(flex: 5, child: visual),
          ],
        );
      },
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  final String number;
  final IconData icon;
  final String title;
  final String body;

  const _WorkflowStep(this.number, this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(),
      child: Row(
        children: [
          Text(
            number,
            style: const TextStyle(
              color: _landingCyan,
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 18),
          _IconBox(icon),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _landingWhite,
                    fontFamily: 'Poppins',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    color: _landingMuted,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _WorkflowBadge(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: _landingNavyGlass.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _landingCyan.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _landingCyan, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _landingWhite,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySection extends StatelessWidget {
  const _CompanySection({super.key});

  @override
  Widget build(BuildContext context) {
    return _SectionShell(
      eyebrow: 'ABOUT CLOUDMASA',
      title: 'Built by CloudMaSa for practical business systems',
      subtitle:
          'CloudMaSa builds secure, fully digital solutions for organizations that need clear operations, easy tracking, and dependable support.',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: _panelDecoration(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return Flex(
              direction: compact ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  const _CompanyText()
                else
                  const Expanded(flex: 2, child: _CompanyText()),
                SizedBox(width: compact ? 0 : 28, height: compact ? 22 : 0),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Pill('CloudMaSa'),
                    _Pill('Digital Workflow'),
                    _Pill('QR Attendance'),
                    _Pill('Business Automation'),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompanyText extends StatelessWidget {
  const _CompanyText();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'TЯAKR is part of CloudMaSa\'s business software work: simplifying attendance, employee workflows, compliance-style tracking, and operational reporting for modern teams.',
      style: TextStyle(
        color: _landingMuted,
        fontSize: 17,
        height: 1.55,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _SocialFooter extends StatelessWidget {
  const _SocialFooter({super.key});

  static const _youtube = 'https://www.youtube.com/@CloudMaSa_Technologies';
  static const _facebook =
      'https://www.facebook.com/people/CloudMasa-T/pfbid0W1cEry6U655S56vUrQAXsqH6fb3NYqn3YD6aedZAANbiVrXkjumyqPLWVQzgBDNel/';
  static const _instagram = 'https://www.instagram.com/cloudmasa_technology/';
  static const _github = 'https://github.com/CloudMasa-Tech';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 42),
      color: _landingBackground,
      child: DefaultTextStyle.merge(
        style: GoogleFonts.inter(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1520),
            child: Column(
              children: [
                const _FooterTopContent(),
                const SizedBox(height: 48),
                Container(
                  height: 1,
                  color: _landingOverlay.withValues(alpha: .08),
                ),
                const SizedBox(height: 34),
                _FooterSocialBar(
                  onCompany: () => Scrollable.ensureVisible(
                    context,
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  ),
                  onYoutube: () => _openExternal(_youtube),
                  onInstagram: () => _openExternal(_instagram),
                  onFacebook: () => _openExternal(_facebook),
                  onGithub: () => _openExternal(_github),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterTopContent extends StatelessWidget {
  const _FooterTopContent();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        if (compact) {
          return const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FooterCompanyDetails(),
              SizedBox(height: 42),
              _FooterLinkColumns(),
            ],
          );
        }

        return const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 350, child: _FooterCompanyDetails()),
            SizedBox(width: 54),
            Expanded(child: _FooterLinkColumns()),
          ],
        );
      },
    );
  }
}

class _FooterCompanyDetails extends StatelessWidget {
  const _FooterCompanyDetails();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TrakrLogo(
          size: 126,
        ),
        SizedBox(height: 22),
        Text(
          'Smart attendance and workforce tracking for modern '
          'organizations. Secure, simple, and fully digital.',
          style: TextStyle(
            color: _landingMuted,
            fontSize: 16,
            height: 1.62,
            fontWeight: FontWeight.w400,
          ),
        ),
        SizedBox(height: 28),
        _FooterDetail(
          icon: Icons.location_on_outlined,
          text: 'Vinayagar Kovil Street,\n'
              'Kurumbapet, Pondicherry-605 009,\n'
              'India',
        ),
        SizedBox(height: 15),
        _FooterDetail(
          icon: Icons.phone_in_talk_outlined,
          text: '+91 63645 62818',
        ),
        SizedBox(height: 15),
        _FooterDetail(
          icon: Icons.phone_outlined,
          text: '0413-2262818',
        ),
        SizedBox(height: 15),
        _FooterDetail(
          icon: Icons.mail_outline_rounded,
          text: 'support@cloudmasa.com',
        ),
      ],
    );
  }
}

class _FooterDetail extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FooterDetail({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: _landingOrange),
        const SizedBox(width: 13),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              color: _landingMuted,
              fontSize: 16,
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _FooterLinkColumns extends StatelessWidget {
  const _FooterLinkColumns();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 62,
      runSpacing: 42,
      alignment: WrapAlignment.spaceBetween,
      children: [
        _FooterLinks(
          title: 'SERVICES',
          items: [
            'QR Attendance',
            'Location Verification',
            'Leave Management',
            'Approval Workflows',
            'Reports & Analytics',
            'Employee Directory',
          ],
        ),
        _FooterLinks(
          title: 'RESOURCES',
          items: [
            'Documentation',
            'How It Works',
            'Help Center',
            'Security',
          ],
        ),
        _FooterLinks(
          title: 'COMPANY',
          items: [
            'About Us',
            'Privacy Policy',
            'Refund Policy',
            'Terms of Service',
          ],
        ),
      ],
    );
  }
}

class _FooterLinks extends StatelessWidget {
  final String title;
  final List<String> items;

  const _FooterLinks({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 194,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _landingOrange,
              fontFamily: 'Poppins',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 27),
          for (final item in items) ...[
            Text(
              item,
              style: const TextStyle(
                color: _landingMuted,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 22),
          ],
        ],
      ),
    );
  }
}

class _FooterSocialBar extends StatelessWidget {
  final VoidCallback onCompany;
  final VoidCallback onYoutube;
  final VoidCallback onInstagram;
  final VoidCallback onFacebook;
  final VoidCallback onGithub;

  const _FooterSocialBar({
    required this.onCompany,
    required this.onYoutube,
    required this.onInstagram,
    required this.onFacebook,
    required this.onGithub,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 800;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 18 : 28,
            vertical: compact ? 24 : 28,
          ),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_landingFooterBg, _landingFooterBg2],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _landingBlue.withValues(alpha: .16)),
            boxShadow: [
              BoxShadow(
                color: _landingBlue.withValues(alpha: .16),
                blurRadius: 34,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Flex(
            direction: compact ? Axis.vertical : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment:
                compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              const _FooterCopyrightBlock(),
              SizedBox(width: compact ? 0 : 38, height: compact ? 26 : 0),
              if (!compact)
                Container(
                  width: 1,
                  height: 96,
                  color: _landingBlue.withValues(alpha: .30),
                ),
              SizedBox(width: compact ? 0 : 38, height: compact ? 26 : 0),
              if (compact)
                Column(
                  crossAxisAlignment: compact
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    const Text(
                      'FOLLOW US ON',
                      style: TextStyle(
                        color: _landingBlue,
                        fontFamily: 'Poppins',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 18,
                      runSpacing: 16,
                      children: [
                        _GlowSocialButton(
                          tooltip: 'Company',
                          icon: Icons.business_rounded,
                          colors: const [_landingCardBlueA, _landingCardBlueB],
                          onTap: onCompany,
                        ),
                        _GlowSocialButton(
                          tooltip: 'YouTube',
                          icon: Icons.play_arrow_rounded,
                          colors: const [_landingCardBlueC, _landingCardBlueD],
                          onTap: onYoutube,
                        ),
                        _GlowSocialButton(
                          tooltip: 'Instagram',
                          icon: Icons.camera_alt_rounded,
                          colors: const [
                            _landingFeatureGold,
                            _landingFeaturePink,
                            _landingFeaturePurple,
                          ],
                          onTap: onInstagram,
                        ),
                        _GlowSocialButton(
                          tooltip: 'Facebook',
                          icon: Icons.facebook_rounded,
                          colors: const [_landingCardBlueE, _landingCardBlueF],
                          onTap: onFacebook,
                        ),
                        const _GlowSocialButton(
                          tooltip: 'LinkedIn',
                          label: 'in',
                          colors: [_landingCardBlueG, _landingCardBlueH],
                        ),
                        _GlowSocialButton(
                          tooltip: 'GitHub',
                          label: '{}',
                          colors: const [
                            _landingFeatureSlate,
                            _landingFeatureSlateDeep
                          ],
                          onTap: onGithub,
                        ),
                      ],
                    ),
                  ],
                )
              else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'FOLLOW US ON',
                        style: TextStyle(
                          color: _landingBlue,
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 18,
                        runSpacing: 16,
                        children: [
                          _GlowSocialButton(
                            tooltip: 'Company',
                            icon: Icons.business_rounded,
                            colors: const [
                              _landingCardBlueA,
                              _landingCardBlueB
                            ],
                            onTap: onCompany,
                          ),
                          _GlowSocialButton(
                            tooltip: 'YouTube',
                            icon: Icons.play_arrow_rounded,
                            colors: const [
                              _landingCardBlueC,
                              _landingCardBlueD
                            ],
                            onTap: onYoutube,
                          ),
                          _GlowSocialButton(
                            tooltip: 'Instagram',
                            icon: Icons.camera_alt_rounded,
                            colors: const [
                              _landingFeatureGold,
                              _landingFeaturePink,
                              _landingFeaturePurple,
                            ],
                            onTap: onInstagram,
                          ),
                          _GlowSocialButton(
                            tooltip: 'Facebook',
                            icon: Icons.facebook_rounded,
                            colors: const [
                              _landingCardBlueE,
                              _landingCardBlueF
                            ],
                            onTap: onFacebook,
                          ),
                          const _GlowSocialButton(
                            tooltip: 'LinkedIn',
                            label: 'in',
                            colors: [_landingCardBlueG, _landingCardBlueH],
                          ),
                          _GlowSocialButton(
                            tooltip: 'GitHub',
                            label: '{}',
                            colors: const [
                              _landingFeatureSlate,
                              _landingFeatureSlateDeep
                            ],
                            onTap: onGithub,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FooterCopyrightBlock extends StatelessWidget {
  const _FooterCopyrightBlock();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FooterShieldMark(),
        SizedBox(width: 22),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '© 2026 CloudMaSa Innovation Lab Pvt Ltd.',
                style: TextStyle(
                  color: _landingWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'All rights reserved.',
                style: TextStyle(
                  color: _landingMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterShieldMark extends StatefulWidget {
  const _FooterShieldMark();

  @override
  State<_FooterShieldMark> createState() => _FooterShieldMarkState();
}

class _FooterShieldMarkState extends State<_FooterShieldMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = .55 + math.sin(_controller.value * math.pi) * .45;
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _landingBlue.withValues(alpha: .35 + pulse * .22),
                blurRadius: 18 + pulse * 12,
              ),
            ],
          ),
          child: child,
        );
      },
      child: const Icon(
        Icons.verified_user_rounded,
        color: _landingWhite,
        size: 54,
      ),
    );
  }
}

class _GlowSocialButton extends StatefulWidget {
  final String tooltip;
  final IconData? icon;
  final String? label;
  final List<Color> colors;
  final VoidCallback? onTap;

  const _GlowSocialButton({
    required this.tooltip,
    required this.colors,
    this.icon,
    this.label,
    this.onTap,
  });

  @override
  State<_GlowSocialButton> createState() => _GlowSocialButtonState();
}

class _GlowSocialButtonState extends State<_GlowSocialButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = .55 + math.sin(_controller.value * math.pi) * .45;
            return AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              scale: _hovered ? 1.1 : 1,
              child: Transform.translate(
                offset: Offset(0, -pulse * (_hovered ? 3 : 1.5)),
                child: child,
              ),
            );
          },
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(32),
            child: Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.colors,
                ),
                border:
                    Border.all(color: _landingOverlay.withValues(alpha: .18)),
                boxShadow: [
                  BoxShadow(
                    color: widget.colors.first.withValues(alpha: .62),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: widget.icon != null
                  ? Icon(widget.icon, color: _landingWhite, size: 31)
                  : Text(
                      widget.label ?? '',
                      style: const TextStyle(
                        color: _landingWhite,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

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
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 22 : 80,
        vertical: compact ? 46 : 72,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1260),
        child: Column(
          children: [
            Text(
              eyebrow,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _landingOrange,
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _landingWhite,
                fontFamily: 'Poppins',
                fontSize: compact ? 32 : 48,
                height: 1.12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _landingMuted,
                  fontSize: 18,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(height: 42),
            child,
          ],
        ),
      ),
    );
  }
}

class _MarqueeCards extends StatefulWidget {
  final List<Widget> children;
  final VoidCallback onCardTap;

  const _MarqueeCards({
    required this.children,
    required this.onCardTap,
  });

  @override
  State<_MarqueeCards> createState() => _MarqueeCardsState();
}

class _MarqueeCardsState extends State<_MarqueeCards>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 24),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 18.0;
        final cardWidth = math.min(320.0, constraints.maxWidth * .78);
        final singleWidth = widget.children.length * (cardWidth + spacing);

        return SizedBox(
          height: 238,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final offset = -singleWidth + singleWidth * _controller.value;
                return OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: 0,
                  maxWidth: singleWidth * 2,
                  child: Transform.translate(
                    offset: Offset(offset, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var repeat = 0; repeat < 2; repeat++)
                          for (final child in widget.children)
                            Padding(
                              padding: const EdgeInsets.only(right: spacing),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: widget.onCardTap,
                                    child: SizedBox(
                                      width: cardWidth,
                                      height: 220,
                                      child: child,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _StaticCards extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onCardTap;

  const _StaticCards({
    required this.children,
    required this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 18.0;
        final columns = constraints.maxWidth >= 980
            ? children.length.clamp(1, 4).toInt()
            : constraints.maxWidth >= 620
                ? 2
                : 1;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onCardTap,
                    child: SizedBox(
                      width: cardWidth,
                      height: 220,
                      child: child,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard(this.icon, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccentForIcon(icon);
    return Container(
      constraints: const BoxConstraints(minHeight: 170),
      padding: const EdgeInsets.all(20),
      decoration: _referenceCardDecoration(accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconBox(icon, accent: accent, size: 62, iconSize: 31),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: _landingWhite,
              fontFamily: 'Poppins',
              fontSize: 18,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: const TextStyle(
              color: _landingSubtext,
              fontSize: 14,
              height: 1.36,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TimelineItem {
  final IconData icon;
  final String title;
  final String body;

  const _TimelineItem(this.icon, this.title, this.body);
}

class _TimelineCard extends StatelessWidget {
  final int index;
  final _TimelineItem item;

  const _TimelineCard({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    final accent = _cardAccentForIcon(item.icon);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _referenceCardDecoration(accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(item.icon, accent: accent, size: 62, iconSize: 31),
              const Spacer(),
              Container(
                width: 38,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: .12)),
                ),
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: accent,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            item.title,
            style: const TextStyle(
              color: _landingWhite,
              fontFamily: 'Poppins',
              fontSize: 18,
              height: 1.15,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Text(
            item.body,
            style: const TextStyle(
              color: _landingSubtext,
              fontSize: 14,
              height: 1.36,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color? accent;
  final double size;
  final double iconSize;

  const _IconBox(
    this.icon, {
    this.accent,
    this.size = 56,
    this.iconSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? _landingBlue;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .52)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .22),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: RadialGradient(
          center: const Alignment(-.25, -.32),
          radius: 1.05,
          colors: [
            color.withValues(alpha: .26),
            color.withValues(alpha: .10),
            _landingShadow.withValues(alpha: .08),
          ],
        ),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;

  const _Pill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _landingBlue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _landingBlue.withValues(alpha: .20)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: _landingBlue,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

Color _cardAccentForIcon(IconData icon) {
  if (icon == Icons.map_rounded || icon == Icons.location_on_rounded) {
    return _landingStatPink;
  }
  if (icon == Icons.event_available_rounded ||
      icon == Icons.rule_rounded ||
      icon == Icons.notifications_rounded) {
    return _landingOrange;
  }
  if (icon == Icons.analytics_rounded ||
      icon == Icons.speed_rounded ||
      icon == Icons.trending_up_rounded) {
    return _landingCyan;
  }
  if (icon == Icons.admin_panel_settings_rounded ||
      icon == Icons.people_alt_rounded ||
      icon == Icons.person_add_alt_1_rounded) {
    return _landingStatPurple;
  }
  if (icon == Icons.lock_rounded ||
      icon == Icons.visibility_rounded ||
      icon == Icons.security_rounded) {
    return _landingStatGreen;
  }
  return _landingBlue;
}

BoxDecoration _referenceCardDecoration(Color accent) {
  return BoxDecoration(
    color: _landingNavyGlass3.withValues(alpha: .84),
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: accent.withValues(alpha: .34), width: 1.1),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        accent.withValues(alpha: .12),
        _landingNavyGlass3.withValues(alpha: .78),
        _landingDeepNavy.withValues(alpha: .94),
      ],
      stops: const [0, .45, 1],
    ),
    boxShadow: [
      BoxShadow(
        color: accent.withValues(alpha: .13),
        blurRadius: 24,
        offset: const Offset(0, 14),
      ),
      const BoxShadow(
        color: _landingShadowDark,
        blurRadius: 24,
        offset: Offset(0, 16),
      ),
    ],
  );
}

BoxDecoration _panelDecoration() {
  return BoxDecoration(
    color: _landingDarkCard,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: _landingOverlay.withValues(alpha: .05)),
    boxShadow: const [
      BoxShadow(
        color: _landingGlowBlueFaint,
        blurRadius: 20,
        offset: Offset(0, 10),
      ),
    ],
  );
}

class _PanelGridPainter extends CustomPainter {
  const _PanelGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = RadialGradient(
        center: const Alignment(.18, -.28),
        radius: 1.15,
        colors: [
          _landingBlue.withValues(alpha: .18),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final line = Paint()
      ..color = _landingOverlay.withValues(alpha: .045)
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += 56) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    for (var y = 0.0; y <= size.height; y += 56) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
  }

  @override
  bool shouldRepaint(covariant _PanelGridPainter oldDelegate) => false;
}

class _NetworkBackdropPainter extends CustomPainter {
  final Animation<double> pulse;

  const _NetworkBackdropPainter(this.pulse) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final pulseValue = .5 + math.sin(pulse.value * math.pi) * .5;
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _landingFooterBg3,
          _landingBackground,
          _landingFooterBg4,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          _landingBlue.withValues(alpha: .12 + pulseValue * .10),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * .18, size.height * .22),
          radius: size.width * .42,
        ),
      );
    canvas.drawRect(Offset.zero & size, glow);

    final sweep = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          _landingBlue.withValues(alpha: .02 + pulseValue * .05),
          Colors.transparent,
        ],
        stops: const [.18, .5, .82],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sweep);

    final linePaint = Paint()
      ..color = _landingBlue.withValues(alpha: .06 + pulseValue * .05)
      ..strokeWidth = 1;
    final dotPaint = Paint()
      ..color = _landingBlue.withValues(alpha: .17 + pulseValue * .13);

    for (var i = 0; i < 34; i++) {
      final x = ((i * 97) % 1000) / 1000 * size.width;
      final y = ((i * 173) % 1000) / 1000 * size.height;
      final nextX = (((i + 5) * 97) % 1000) / 1000 * size.width;
      final nextY = (((i + 7) * 173) % 1000) / 1000 * size.height;
      final start = Offset(x, y);
      final end = Offset(nextX, nextY);
      if ((start - end).distance < size.shortestSide * .32) {
        canvas.drawLine(start, end, linePaint);
      }
      canvas.drawCircle(
          start, 2.2 + math.sin(i.toDouble()).abs() * 1.8, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkBackdropPainter oldDelegate) {
    return oldDelegate.pulse != pulse;
  }
}
