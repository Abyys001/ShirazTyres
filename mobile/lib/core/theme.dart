import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ShirazTyres palette, shared with the web apps' design tokens
/// (`docs/design-tokens.md`).
///
/// Two colours carry the identity — gold #FFD700 on the near-black #0B1315 —
/// over a cool slate neutral ramp. Gold is a scarce resource here: it marks the
/// one thing the screen wants you to do, and nothing else.
///
/// The same logic runs in daylight. The light palette is not the dark one
/// inverted: the neutral ramp flips, the gold *fill* stays exactly as it is
/// (a gold button with near-black text is the brand, at either brightness),
/// and gold-as-ink darkens to #8A6200 so a word or an icon in it still reads
/// on white. Everything else keeps its job, at the contrast that job needs.
///
/// Colours are resolved from the theme rather than read off a constant, so a
/// screen never hard-codes a brightness. In a widget:
///
/// ```dart
/// final palette = context.palette;
/// ... color: palette.gold
/// ```
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.brightness,
    required this.gold,
    required this.goldFill,
    required this.goldStrong,
    required this.goldDim,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.line,
    required this.lineStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.onGold,
    required this.accent,
    required this.info,
    required this.success,
    required this.warning,
    required this.danger,
    required this.scrim,
    required this.shadow,
  });

  final Brightness brightness;

  /// Gold as ink: text, icons, borders, anything drawn *on* the canvas.
  final Color gold;

  /// Gold as a fill: the primary button, the logo, the step bar. Identical in
  /// both themes — this is the colour people recognise the app by.
  final Color goldFill;

  final Color goldStrong;

  /// The tinted container behind a gold-marked block.
  final Color goldDim;

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color line;
  final Color lineStrong;

  final Color ink;
  final Color inkMuted;
  final Color inkSubtle;
  final Color onGold;

  final Color accent;
  final Color info;
  final Color success;
  final Color warning;
  final Color danger;

  /// Behind a modal. Heavier in light mode, where a sheet has less of its own
  /// contrast to separate it from what is underneath.
  final Color scrim;

  /// Light mode separates surfaces with a shadow where dark mode separates them
  /// with a lighter fill; in dark mode this is transparent and costs nothing.
  final Color shadow;

  bool get isDark => brightness == Brightness.dark;

  /// Night: high-contrast and low-glare. These apps get used at 2am on a hard
  /// shoulder, and a white screen there is hostile.
  static const dark = Palette(
    brightness: Brightness.dark,
    gold: Color(0xFFFFD700),
    goldFill: Color(0xFFFFD700),
    goldStrong: Color(0xFFFBBF24),
    goldDim: Color(0xFF3F2E00),
    canvas: Color(0xFF0B1315),
    surface: Color(0xFF101A1D),
    surfaceRaised: Color(0xFF162327),
    surfaceSunken: Color(0xFF080F11),
    line: Color(0xFF1F3036),
    lineStrong: Color(0xFF2E454D),
    ink: Color(0xFFF8FAFC),
    inkMuted: Color(0xFFB6C4CB),
    inkSubtle: Color(0xFF7F949D),
    onGold: Color(0xFF0B1315),
    accent: Color(0xFF0078A8),
    info: Color(0xFF3B82F6),
    success: Color(0xFF4ADE80),
    warning: Color(0xFFFACC15),
    danger: Color(0xFFDC2626),
    scrim: Color(0xB3000000),
    shadow: Color(0x00000000),
  );

  /// Day: the same structure in daylight, for a phone held at arm's length in
  /// the sun. The neutrals are cool rather than pure white so the gold does not
  /// have to fight a glare, and every ink tone clears 4.5:1 on the surface it
  /// is meant to sit on.
  static const light = Palette(
    brightness: Brightness.light,
    gold: Color(0xFF8A6200),
    goldFill: Color(0xFFFFD700),
    goldStrong: Color(0xFFB07D00),
    goldDim: Color(0xFFFFF3CC),
    canvas: Color(0xFFF1F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFE7EEF2),
    surfaceSunken: Color(0xFFF5F8FA),
    line: Color(0xFFDCE5EA),
    lineStrong: Color(0xFFB9C8D0),
    ink: Color(0xFF0B1315),
    inkMuted: Color(0xFF48606A),
    inkSubtle: Color(0xFF647C86),
    onGold: Color(0xFF0B1315),
    accent: Color(0xFF00648D),
    info: Color(0xFF1D4ED8),
    success: Color(0xFF127C46),
    warning: Color(0xFF8A5A00),
    danger: Color(0xFFB91C1C),
    scrim: Color(0x66101A1D),
    shadow: Color(0x14172A33),
  );

  /// Section eyebrows: wide-tracked upper case above a group of fields or cards,
  /// to say what the group is without spending a heading on it.
  ///
  /// Deliberately not tiny. Nothing in either app is set below 12.5pt: these are
  /// read one-handed, at the roadside, in weather, and a caption nobody can read
  /// is a caption that should not have been written.
  TextStyle get eyebrow => TextStyle(
        fontFamily: Fonts.sans,
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: inkMuted,
      );

  /// Registration plates and invoice totals read as data, not prose.
  TextStyle get plate => TextStyle(
        fontFamily: Fonts.mono,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.5,
        color: ink,
      );

  /// Job references, money, and anything else that lines up in a column.
  TextStyle get mono => TextStyle(
        fontFamily: Fonts.mono,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: inkMuted,
      );

  /// The gold wash behind a hero: strongest at the top-left, gone by the middle.
  /// Keeps a full-bleed panel from reading as a flat rectangle. Lighter in day
  /// mode, where the same alpha over white would read as a stain.
  LinearGradient get wash => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          goldFill.withValues(alpha: isDark ? 0.12 : 0.20),
          goldFill.withValues(alpha: isDark ? 0.04 : 0.08),
          goldFill.withValues(alpha: 0),
        ],
        stops: const <double>[0, 0.45, 1],
      );

  /// The elevation light mode uses in place of a lighter fill.
  List<BoxShadow> get lift => isDark
      ? const <BoxShadow>[]
      : <BoxShadow>[BoxShadow(color: shadow, blurRadius: 18, offset: const Offset(0, 6))];

  /// Status colours are shared by the chip, the timeline and the map.
  Color status(String status) {
    switch (status) {
      case 'submitted':
      case 'dispatching':
      case 'unclaimed':
        return warning;
      case 'assigned':
      case 'accepted':
        return info;
      case 'en_route':
      case 'arrived':
        return accent;
      case 'in_progress':
        return gold;
      case 'completed':
        return success;
      case 'cancelled':
        return inkSubtle;
      default:
        return inkMuted;
    }
  }

  /// Nothing ever needs a partial copy of a palette — a screen picks one of the
  /// two — so this is the identity the framework requires and no more.
  @override
  Palette copyWith() => this;

  /// A real interpolation, so switching theme cross-fades every token at once
  /// rather than snapping. Brightness follows the halfway point.
  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      brightness: t < 0.5 ? brightness : other.brightness,
      gold: mix(gold, other.gold),
      goldFill: mix(goldFill, other.goldFill),
      goldStrong: mix(goldStrong, other.goldStrong),
      goldDim: mix(goldDim, other.goldDim),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      line: mix(line, other.line),
      lineStrong: mix(lineStrong, other.lineStrong),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkSubtle: mix(inkSubtle, other.inkSubtle),
      onGold: mix(onGold, other.onGold),
      accent: mix(accent, other.accent),
      info: mix(info, other.info),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      scrim: mix(scrim, other.scrim),
      shadow: mix(shadow, other.shadow),
    );
  }
}

/// How every widget gets at the palette. Reading it through the theme is what
/// makes a screen follow the light/dark switch without knowing it exists.
extension PaletteContext on BuildContext {
  Palette get palette => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

/// The 4pt spacing scale everything lays out on. Named, so a screen never
/// reaches for an arbitrary number and drifts out of rhythm with the others.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
}

/// Durations, so nothing on screen animates at a number somebody typed once.
/// Short enough that an impatient thumb never waits on the interface.
abstract final class Motion {
  static const fast = Duration(milliseconds: 140);
  static const normal = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 400);
}

/// Two radii: [card] for anything that holds content, [pill] for anything that
/// holds a single word.
abstract final class Radii {
  static const control = 14.0;
  static const card = 20.0;
  static const pill = 999.0;

  static const cardShape = BorderRadius.all(Radius.circular(card));
  static const controlShape = BorderRadius.all(Radius.circular(control));
}

/// Headings and body are set in the platform's own UI sans — `ui-sans-serif` in
/// the design tokens, which is Roboto on Android and SF on iOS. A null family is
/// how Flutter spells that, and it is why neither face is vendored: the system
/// already has one, and it is the face every other app on the phone uses.
///
/// JetBrains Mono stays vendored, because the tabular figures registrations and
/// money line up in are not something the platform face can be relied on for.
abstract final class Fonts {
  static const String? display = null;
  static const String? sans = null;
  static const mono = 'JetBrainsMono';
}

/// High-contrast, big-target theme in both brightnesses: these apps get used at
/// night on a hard shoulder, and at noon in traffic.
ThemeData buildTheme(Brightness brightness) {
  final palette = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: palette.gold,
    onPrimary: palette.onGold,
    primaryContainer: palette.goldDim,
    onPrimaryContainer: palette.gold,
    secondary: palette.accent,
    onSecondary: brightness == Brightness.dark ? palette.ink : Colors.white,
    tertiary: palette.info,
    onTertiary: Colors.white,
    error: palette.danger,
    onError: Colors.white,
    errorContainer: brightness == Brightness.dark ? const Color(0xFF2A1114) : const Color(0xFFFDECEC),
    onErrorContainer: brightness == Brightness.dark ? const Color(0xFFFECACA) : const Color(0xFF7F1D1D),
    surface: palette.surface,
    onSurface: palette.ink,
    surfaceContainerLowest: palette.surfaceSunken,
    surfaceContainer: palette.surface,
    surfaceContainerHighest: palette.surfaceRaised,
    onSurfaceVariant: palette.inkMuted,
    outline: palette.line,
    outlineVariant: palette.line,
    scrim: palette.scrim,
    shadow: palette.shadow,
  );

  final textTheme = _textTheme(palette);
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    fontFamily: Fonts.sans,
    scaffoldBackgroundColor: palette.canvas,
    canvasColor: palette.canvas,
    dividerColor: palette.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: textTheme,
    dividerTheme: DividerThemeData(color: palette.line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.canvas,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.canvas,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontFamily: Fonts.display,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: palette.ink,
      ),
    ),
    // Size.fromHeight is an infinite *minimum width*: these buttons fill
    // whatever bounds them. Inside a Row, which hands its children unbounded
    // width, that fails the whole subtree to lay out — override minimumSize
    // there.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.goldFill,
        foregroundColor: palette.onGold,
        disabledBackgroundColor: isDark ? palette.surfaceRaised : palette.surfaceSunken,
        disabledForegroundColor: palette.inkSubtle,
        minimumSize: const Size.fromHeight(54),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: const TextStyle(
          fontFamily: Fonts.sans,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.controlShape),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        backgroundColor: Colors.transparent,
        side: BorderSide(color: palette.lineStrong),
        disabledForegroundColor: palette.inkSubtle,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        textStyle: const TextStyle(
          fontFamily: Fonts.sans,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.controlShape),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: palette.gold,
        textStyle: const TextStyle(fontFamily: Fonts.sans, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: palette.inkMuted),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceSunken,
      hintStyle: TextStyle(color: palette.inkSubtle, fontWeight: FontWeight.w400),
      labelStyle: TextStyle(color: palette.inkMuted),
      floatingLabelStyle: TextStyle(color: palette.gold, fontWeight: FontWeight.w600),
      prefixIconColor: palette.inkSubtle,
      suffixIconColor: palette.inkSubtle,
      border: _fieldBorder(palette.line),
      enabledBorder: _fieldBorder(palette.line),
      focusedBorder: _fieldBorder(palette.gold, width: 1.6),
      errorBorder: _fieldBorder(palette.danger),
      focusedErrorBorder: _fieldBorder(palette.danger, width: 1.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: 18),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.cardShape,
        side: BorderSide(color: palette.line),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark ? palette.surfaceRaised : palette.surfaceSunken,
      side: BorderSide(color: palette.line),
      labelStyle: TextStyle(
        fontFamily: Fonts.sans,
        color: palette.inkMuted,
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: palette.ink,
      iconColor: palette.inkSubtle,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardShape),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? palette.onGold : palette.inkSubtle,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? palette.goldFill
            : (isDark ? palette.surfaceRaised : palette.surfaceSunken),
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? palette.goldFill : palette.lineStrong,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? palette.goldFill : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(palette.onGold),
      side: BorderSide(color: palette.lineStrong, width: 1.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(palette.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? palette.surfaceRaised : const Color(0xFF16242A),
      contentTextStyle: TextStyle(
        fontFamily: Fonts.sans,
        color: isDark ? palette.ink : Colors.white,
        fontSize: 14,
      ),
      actionTextColor: palette.goldFill,
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(Space.lg),
      shape: const RoundedRectangleBorder(borderRadius: Radii.controlShape),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: palette.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.card)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      barrierColor: palette.scrim,
      shape: const RoundedRectangleBorder(borderRadius: Radii.cardShape),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: palette.gold,
      linearTrackColor: isDark ? palette.surfaceRaised : palette.surfaceSunken,
      circularTrackColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? palette.surfaceRaised : const Color(0xFF16242A),
        borderRadius: Radii.controlShape,
      ),
      textStyle: TextStyle(color: isDark ? palette.ink : Colors.white, fontSize: 13),
    ),
  );
}

OutlineInputBorder _fieldBorder(Color colour, {double width = 1}) => OutlineInputBorder(
      borderRadius: Radii.controlShape,
      borderSide: BorderSide(color: colour, width: width),
    );

/// One face for everything it says out loud. With headings and body sharing the
/// platform sans, weight, size and tracking are the whole voice — hence headings
/// tight and heavy against roomy body.
TextTheme _textTheme(Palette palette) => TextTheme(
      displayLarge: TextStyle(
          fontFamily: Fonts.display, fontSize: 44, fontWeight: FontWeight.w700, letterSpacing: -1.6, height: 1.05, color: palette.ink),
      displaySmall: TextStyle(
          fontFamily: Fonts.display, fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -1, height: 1.1, color: palette.ink),
      headlineMedium: TextStyle(
          fontFamily: Fonts.display, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15, color: palette.ink),
      headlineSmall: TextStyle(
          fontFamily: Fonts.display, fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.2, color: palette.ink),
      titleLarge: TextStyle(
          fontFamily: Fonts.display, fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: palette.ink),
      titleMedium: TextStyle(
          fontFamily: Fonts.sans, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.1, color: palette.ink),
      titleSmall: TextStyle(
          fontFamily: Fonts.sans, fontSize: 15, fontWeight: FontWeight.w600, color: palette.inkMuted),
      bodyLarge: TextStyle(fontFamily: Fonts.sans, fontSize: 16, height: 1.5, color: palette.ink),
      bodyMedium: TextStyle(fontFamily: Fonts.sans, fontSize: 15, height: 1.5, color: palette.inkMuted),
      bodySmall: TextStyle(fontFamily: Fonts.sans, fontSize: 14, height: 1.45, color: palette.inkMuted),
      labelLarge: TextStyle(fontFamily: Fonts.sans, fontSize: 15, fontWeight: FontWeight.w600, color: palette.ink),
      labelMedium: TextStyle(fontFamily: Fonts.sans, fontSize: 13.5, fontWeight: FontWeight.w600, color: palette.inkMuted),
      labelSmall: TextStyle(
          fontFamily: Fonts.sans, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: palette.inkMuted),
    );
