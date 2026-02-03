// lib/core/theme.dart
/*
  Enhanced Modern Design System for College App
  Features:
  - Material 3 with cyberpunk influences
  - Smooth animations and modern visual effects
  - Glass morphism effects
  - Gradient overlays
  - All original class/function names preserved
*/

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ====================== DESIGN TOKENS ======================

class AppColors {
  AppColors._();

  // Primary Palette (Enhanced)
  static const Color primary = Color(0xFF00D2FF); // Cyber blue
  static const Color primaryVariant = Color(0xFF3A7BD5);
  static const Color secondary = Color(0xFFFF00FF); // Neon pink
  static const Color tertiary = Color(0xFF00FF9D); // Neon green

  // Semantic Colors (Enhanced)
  static const Color success = Color(0xFF00FF9D);
  static const Color warning = Color(0xFFFFD700);
  static const Color error = Color(0xFFFF5252);
  static const Color info = Color(0xFF00D2FF);

  // Neutral Scale (Enhanced)
  static const Color black = Color(0xFF0A0A0F);
  static const Color gray90 = Color(0xFF141420);
  static const Color gray80 = Color(0xFF1E1E2E);
  static const Color gray70 = Color(0xFF2D2D3D);
  static const Color gray60 = Color(0xFF3A3A4D);
  static const Color gray50 = Color(0xFF5A5A7A);
  static const Color gray40 = Color(0xFF8A8AAA);
  static const Color gray30 = Color(0xFFB0B0D0);
  static const Color gray20 = Color(0xFFD0D0E8);
  static const Color gray10 = Color(0xFFE8E8F8);
  static const Color gray5 = Color(0xFFF5F5FF);
  static const Color white = Color(0xFFFFFFFF);

  // Surface Colors (Enhanced)
  static const Color surface = Color(0xFF141420);
  static const Color surfaceVariant = Color(0xFF1E1E2E);
  static const Color background = Color(0xFF0A0A0F);

  // Status Backgrounds (Enhanced)
  static const Color successBg = Color(0x1500FF9D);
  static const Color warningBg = Color(0x15FFFF00);
  static const Color errorBg = Color(0x15FF5252);
  static const Color infoBg = Color(0x1500D2FF);

  // Glass Colors (New)
  static const Color glassWhite = Color(0x15FFFFFF);
  static const Color glassBlack = Color(0x0D000000);
  static const Color glassPrimary = Color(0x1A00D2FF);

  // Gradients (Enhanced)
  static const Gradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5), Color(0xFF00B4DB)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const Gradient secondaryGradient = LinearGradient(
    colors: [Color(0xFFFF00FF), Color(0xFFFF6BFF), Color(0xFF9400D3)],
    stops: [0.0, 0.7, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const Gradient premiumGradient = LinearGradient(
    colors: [Color(0xFF00FF87), Color(0xFF60EFFF), Color(0xFF0061FF)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // New Cyber Gradients
  static const Gradient cyberBlue = primaryGradient;
  static const Gradient neonPurple = secondaryGradient;
  static const Gradient acidGreen = premiumGradient;
}

class AppSpacing {
  AppSpacing._();

  // Base unit: 4px
  static const double quarter = 1.0;
  static const double half = 2.0;
  static const double base = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Screen margins
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: lg,
  );

  // Component spacing
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
  static const EdgeInsets buttonPadding = EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );
}

class AppRadius {
  AppRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double round = 999.0;

  // Common shapes
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius button = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(round));
  static const BorderRadius sheet = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
  );
}

class AppShadows {
  AppShadows._();

  static const BoxShadow xs = BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 2,
    offset: Offset(0, 1),
  );

  static const BoxShadow sm = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 4,
    offset: Offset(0, 2),
  );

  static const BoxShadow md = BoxShadow(
    color: Color(0x1F000000),
    blurRadius: 8,
    offset: Offset(0, 4),
  );

  static const BoxShadow lg = BoxShadow(
    color: Color(0x29000000),
    blurRadius: 16,
    offset: Offset(0, 8),
  );

  static const BoxShadow xl = BoxShadow(
    color: Color(0x3D000000),
    blurRadius: 24,
    offset: Offset(0, 12),
  );

  // Enhanced shadows with glow effects
  static List<BoxShadow> get neonBlueGlow => [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.5),
      blurRadius: 20,
      spreadRadius: 0,
      offset: Offset.zero,
    ),
    BoxShadow(
      color: AppColors.primary.withOpacity(0.3),
      blurRadius: 40,
      spreadRadius: -5,
      offset: const Offset(0, 10),
    ),
  ];

  static List<BoxShadow> get neonPinkGlow => [
    BoxShadow(
      color: AppColors.secondary.withOpacity(0.5),
      blurRadius: 25,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: AppColors.secondary.withOpacity(0.2),
      blurRadius: 50,
      spreadRadius: -10,
    ),
  ];

  static List<BoxShadow> get floatingCard => [
    BoxShadow(
      color: Colors.black.withOpacity(0.3),
      blurRadius: 30,
      spreadRadius: -10,
      offset: const Offset(0, 20),
    ),
    BoxShadow(
      color: AppColors.primary.withOpacity(0.1),
      blurRadius: 60,
      spreadRadius: -20,
    ),
  ];
}

class AppAnimations {
  AppAnimations._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration pageTransition = Duration(milliseconds: 250);

  static const Curve standardCurve = Curves.easeInOut;
  static const Curve bounceCurve = Curves.elasticOut;
  static const Curve shimmerCurve = Curves.linear;
}

// ====================== TYPOGRAPHY ======================

class AppTypography {
  AppTypography._();

  // Using Rajdhani for futuristic look
  static TextStyle inter({
    double? fontSize,
    FontWeight? fontWeight,
    double? height,
    Color? color,
    double? letterSpacing,
    bool neon = false,
  }) {
    final style = GoogleFonts.rajdhani(
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      color: color,
      letterSpacing: letterSpacing,
    );

    if (neon && color != null) {
      return style.copyWith(
        shadows: [
          Shadow(
            color: color.withOpacity(0.5),
            blurRadius: 10,
          ),
        ],
      );
    }

    return style;
  }

  // Display
  static TextStyle get displayLarge => inter(
    fontSize: 57,
    fontWeight: FontWeight.w900,
    height: 1.12,
    letterSpacing: -1.5,
  );

  static TextStyle get displayMedium => inter(
    fontSize: 45,
    fontWeight: FontWeight.w800,
    height: 1.16,
    letterSpacing: -1.0,
  );

  static TextStyle get displaySmall => inter(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 1.22,
    letterSpacing: -0.5,
  );

  // Headline
  static TextStyle get headlineLarge => inter(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.5,
  );

  static TextStyle get headlineMedium => inter(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.29,
  );

  static TextStyle get headlineSmall => inter(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.33,
  );

  // Title
  static TextStyle get titleLarge => inter(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.27,
  );

  static TextStyle get titleMedium => inter(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.33,
    letterSpacing: 0.15,
  );

  static TextStyle get titleSmall => inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.43,
    letterSpacing: 0.1,
  );

  // Body
  static TextStyle get bodyLarge => inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.5,
  );

  static TextStyle get bodyMedium => inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: 0.25,
  );

  static TextStyle get bodySmall => inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: 0.4,
  );

  // Label
  static TextStyle get labelLarge => inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.43,
    letterSpacing: 0.1,
  );

  static TextStyle get labelMedium => inter(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.33,
    letterSpacing: 0.5,
  );

  static TextStyle get labelSmall => inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.45,
    letterSpacing: 0.5,
  );
}

// ====================== THEME DATA ======================

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      background: const Color(0xFFF5F7FF),
      surface: const Color(0xFFFFFFFF),
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F7FF),
      canvasColor: const Color(0xFFFFFFFF),

      // Text Theme
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge,
        displayMedium: AppTypography.displayMedium,
        displaySmall: AppTypography.displaySmall,
        headlineLarge: AppTypography.headlineLarge,
        headlineMedium: AppTypography.headlineMedium,
        headlineSmall: AppTypography.headlineSmall,
        titleLarge: AppTypography.titleLarge,
        titleMedium: AppTypography.titleMedium,
        titleSmall: AppTypography.titleSmall,
        bodyLarge: AppTypography.bodyLarge,
        bodyMedium: AppTypography.bodyMedium,
        bodySmall: AppTypography.bodySmall,
        labelLarge: AppTypography.labelLarge,
        labelMedium: AppTypography.labelMedium,
        labelSmall: AppTypography.labelSmall,
      ),

      // App Bar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white.withOpacity(0.9),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: AppColors.black,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.black),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      ),

      // Navigation Bar
      navigationBarTheme: NavigationBarThemeData(
        elevation: 4,
        height: 70,
        backgroundColor: Colors.white.withOpacity(0.95),
        indicatorColor: AppColors.primary.withOpacity(0.15),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            );
          }
          return AppTypography.labelMedium.copyWith(
            color: AppColors.gray50,
          );
        }),
        iconTheme: MaterialStateProperty.resolveWith((states) {
          final color = states.contains(MaterialState.selected)
              ? AppColors.primary
              : AppColors.gray50;
          return IconThemeData(color: color, size: 24);
        }),
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 12,
      ),

      // Cards - Glass Effect
      cardTheme: CardThemeData(
        color: Colors.white.withOpacity(0.9),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(color: Colors.white.withOpacity(0.2)),
        ),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
      ),

      // Buttons - Enhanced
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.white,
          elevation: 0,
          disabledBackgroundColor: AppColors.gray20,
          disabledForegroundColor: AppColors.gray40,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          shadowColor: AppColors.primary.withOpacity(0.3),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: AppSpacing.buttonPadding,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input Fields - Modern
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(
            color: AppColors.gray20.withOpacity(0.5),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.gray40,
        ),
        labelStyle: AppTypography.labelLarge.copyWith(
          color: AppColors.gray60,
        ),
        floatingLabelStyle: AppTypography.labelLarge.copyWith(
          color: AppColors.primary,
        ),
      ),

      // Dialogs
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
        ),
      ),

      // Dividers
      dividerTheme: DividerThemeData(
        color: AppColors.gray10.withOpacity(0.5),
        thickness: 1,
        space: 0,
      ),

      // Progress Indicators
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.gray10,
        circularTrackColor: AppColors.gray10,
      ),

      // Snackbars
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.gray90,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
        ),
        contentTextStyle: TextStyle(color: AppColors.white),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.gray5,
        selectedColor: AppColors.primary,
        labelStyle: AppTypography.labelMedium,
        secondaryLabelStyle: const TextStyle(color: AppColors.white),
        brightness: Brightness.light,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.round),
        ),
      ),

      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      background: AppColors.background,
      surface: AppColors.surface,
      error: AppColors.error,
    );

    final lightTheme = light();

    return lightTheme.copyWith(
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.background,
      canvasColor: colorScheme.surface,
      cardColor: colorScheme.surface,
      dialogBackgroundColor: colorScheme.surface,
      bottomAppBarTheme: BottomAppBarThemeData(color: colorScheme.surface),

      // Enhanced dark theme overrides
      appBarTheme: lightTheme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: AppColors.white,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.white),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      ),

      cardTheme: lightTheme.cardTheme.copyWith(
        color: AppColors.surface.withOpacity(0.6),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),

      navigationBarTheme: lightTheme.navigationBarTheme.copyWith(
        backgroundColor: AppColors.surface.withOpacity(0.8),
        indicatorColor: AppColors.primary.withOpacity(0.2),
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return AppTypography.labelMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            );
          }
          return AppTypography.labelMedium.copyWith(
            color: AppColors.white.withOpacity(0.7),
          );
        }),
      ),

      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        fillColor: AppColors.surface.withOpacity(0.8),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.white.withOpacity(0.5),
        ),
        labelStyle: AppTypography.labelLarge.copyWith(
          color: AppColors.white.withOpacity(0.7),
        ),
      ),
    );
  }
}

// ====================== REUSABLE UI COMPONENTS ======================

/// Modern scaffold with glass effect option
class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final bool resizeToAvoidBottomInset;
  final Color? backgroundColor;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final PreferredSizeWidget? appBar;
  final bool glassEffect;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.resizeToAvoidBottomInset = true,
    this.backgroundColor,
    this.extendBody = false,
    this.extendBodyBehindAppBar = false,
    this.appBar,
    this.glassEffect = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: key,
      backgroundColor: glassEffect ? Colors.transparent : (backgroundColor ?? theme.scaffoldBackgroundColor),
      appBar: appBar ?? (title != null
          ? AppBar(
        title: Text(
          title!,
          style: AppTypography.titleLarge.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: actions,
        centerTitle: true,
        backgroundColor: glassEffect
            ? (isDark ? AppColors.glassBlack : AppColors.glassWhite)
            : null,
      )
          : null),
      body: glassEffect
          ? Stack(
        children: [
          // Background with blur
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? const LinearGradient(
                  colors: [Color(0xFF0F0C29), Color(0xFF302B63)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
                    : const LinearGradient(
                  colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Content
          SafeArea(
            bottom: false,
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: body,
            ),
          ),
        ],
      )
          : SafeArea(
        bottom: false,
        child: Padding(
          padding: AppSpacing.screenPadding,
          child: body,
        ),
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: bottomNavigationBar,
      drawer: drawer,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
    );
  }
}

/// Enhanced bottom navigation with modern design
class AppBottomNavigation extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavigationDestination> destinations;

  const AppBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.destinations = const [
      NavigationDestination(
        icon: Icon(Icons.groups_outlined),
        selectedIcon: Icon(Icons.groups),
        label: 'Кружки',
      ),
      NavigationDestination(
        icon: Icon(Icons.grade_outlined),
        selectedIcon: Icon(Icons.grade),
        label: 'Оценки',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_balance_wallet_outlined),
        selectedIcon: Icon(Icons.account_balance_wallet),
        label: 'Баланс',
      ),
      NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        selectedIcon: Icon(Icons.receipt_long),
        label: 'Талоны',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Профиль',
      ),
    ],
  });

  @override
  State<AppBottomNavigation> createState() => _AppBottomNavigationState();
}

class _AppBottomNavigationState extends State<AppBottomNavigation> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        boxShadow: isDark ? AppShadows.floatingCard : [AppShadows.lg],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: NavigationBar(
            selectedIndex: widget.currentIndex,
            onDestinationSelected: widget.onTap,
            destinations: widget.destinations,
            animationDuration: AppAnimations.medium,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          ),
        ),
      ),
    );
  }
}

/// Enhanced primary button with neon glow effect
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final IconData? icon;
  final double? width;
  final Color? backgroundColor;
  final bool withGlow;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.icon,
    this.width,
    this.backgroundColor,
    this.withGlow = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppAnimations.fast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        if (!widget.isDisabled && !widget.isLoading) {
          widget.onPressed!();
        }
      },
      onTapCancel: () => _controller.reverse(),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: widget.width,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: widget.withGlow &&
                  _isHovered &&
                  !widget.isDisabled &&
                  !widget.isLoading &&
                  isDark
                  ? AppShadows.neonBlueGlow
                  : _isHovered && !widget.isDisabled && !widget.isLoading
                  ? [AppShadows.md]
                  : [],
            ),
            child: ElevatedButton(
              onPressed: widget.isDisabled || widget.isLoading ? null : widget.onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.backgroundColor ?? theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                shadowColor: Colors.transparent,
              ),
              child: AnimatedSwitcher(
                duration: AppAnimations.fast,
                child: widget.isLoading
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(
                      theme.colorScheme.onPrimary,
                    ),
                  ),
                )
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      widget.label,
                      style: AppTypography.labelLarge.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Enhanced card with glass morphism option
class ModernCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool showShimmer;
  final bool glassEffect;
  final BorderRadius? borderRadius;

  const ModernCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.backgroundColor,
    this.showShimmer = false,
    this.glassEffect = false,
    this.borderRadius,
  });

  @override
  State<ModernCard> createState() => _ModernCardState();
}

class _ModernCardState extends State<ModernCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: AppAnimations.fast,
        child: widget.glassEffect
            ? GlassCard(
          onTap: widget.onTap,
          padding: widget.padding ?? AppSpacing.cardPadding,
          width: double.infinity,
          borderRadius: widget.borderRadius ?? AppRadius.card,
          child: widget.showShimmer
              ? ShimmerWrapper(child: widget.child)
              : widget.child,
        )
            : Card(
          color: widget.backgroundColor,
          child: Padding(
            padding: widget.padding ?? AppSpacing.cardPadding,
            child: widget.showShimmer
                ? ShimmerWrapper(child: widget.child)
                : widget.child,
          ),
        ),
      ),
    );
  }
}

/// Glass morphism card component
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.onTap,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius ?? AppRadius.card,
          color: isDark ? AppColors.glassBlack : AppColors.glassWhite,
          border: Border.all(
            color: Colors.white.withOpacity(isDark ? 0.1 : 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius ?? AppRadius.card,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Padding(
              padding: padding ?? AppSpacing.cardPadding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shimmer effect for loading states
class ShimmerWrapper extends StatefulWidget {
  final Widget child;
  final bool isActive;

  const ShimmerWrapper({
    super.key,
    required this.child,
    this.isActive = true,
  });

  @override
  State<ShimmerWrapper> createState() => _ShimmerWrapperState();
}

class _ShimmerWrapperState extends State<ShimmerWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) return widget.child;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.7 + 0.3 * _controller.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Badge for notifications, status, etc.
class AppBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final double? width;
  final bool withGlow;

  const AppBadge({
    super.key,
    required this.text,
    this.color = AppColors.primary,
    this.textColor = AppColors.white,
    this.width,
    this.withGlow = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.quarter,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.round),
        boxShadow: withGlow && isDark
            ? [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ]
            : null,
      ),
      child: Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Holographic icon with gradient effect
class HolographicIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Gradient gradient;

  const HolographicIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.gradient = AppColors.cyberBlue,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Icon(
        icon,
        size: size,
        color: Colors.white,
      ),
    );
  }
}

// ====================== EXTENSIONS & UTILITIES ======================

extension ContextExtensions on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get textTheme => theme.textTheme;

  bool get isDarkMode => theme.brightness == Brightness.dark;

  void showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(color: AppColors.white),
        ),
        backgroundColor: isError ? AppColors.error : AppColors.gray90,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  void showLoadingDialog([String? message]) {
    showDialog(
      context: this,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(theme.primaryColor),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  message,
                  style: AppTypography.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void hideLoadingDialog() {
    Navigator.of(this).pop();
  }
}

extension StringExtensions on String {
  String get initials {
    final parts = split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (isNotEmpty) {
      return substring(0, 1).toUpperCase();
    }
    return '?';
  }
}

class AppGradients {
  AppGradients._();

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF3A7BD5), Color(0xFF00B4DB)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [Color(0xFFFF00FF), Color(0xFFFF6BFF), Color(0xFF9400D3)],
    stops: [0.0, 0.7, 1.0],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [Color(0xFF00FF87), Color(0xFF60EFFF), Color(0xFF0061FF)],
    stops: [0.0, 0.5, 1.0],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );


  static const LinearGradient blueGreen = LinearGradient(
    colors: [Color(0xFF00D2FF), Color(0xFF00FF9D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}