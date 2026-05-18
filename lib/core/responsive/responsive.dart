import 'package:flutter/widgets.dart';

class ResponsiveBreakpoints {
  const ResponsiveBreakpoints._();

  static const double mobile = 768;
  static const double desktop = 1024;
}

class Responsive {
  const Responsive._();

  static double widthOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width;

  static bool isMobile(BuildContext context) =>
      widthOf(context) < ResponsiveBreakpoints.mobile;

  static bool isTablet(BuildContext context) {
    final width = widthOf(context);
    return width >= ResponsiveBreakpoints.mobile &&
        width < ResponsiveBreakpoints.desktop;
  }

  static bool isDesktop(BuildContext context) =>
      widthOf(context) >= ResponsiveBreakpoints.desktop;

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    if (isDesktop(context)) return desktop ?? tablet ?? mobile;
    if (isTablet(context)) return tablet ?? mobile;
    return mobile;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    return responsiveValue<EdgeInsets>(
      context,
      mobile: const EdgeInsets.fromLTRB(16, 12, 16, 112),
      tablet: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      desktop: const EdgeInsets.fromLTRB(28, 24, 28, 34),
    );
  }

  static int gridColumns(
    BuildContext context, {
    int mobile = 1,
    int tablet = 2,
    int desktop = 4,
  }) {
    return responsiveValue<int>(
      context,
      mobile: mobile,
      tablet: tablet,
      desktop: desktop,
    );
  }
}
