import 'package:flutter/material.dart';

class AppThemeUtils {
  /// Get text color based on theme
  static Color getTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFE6ECF5)
        : const Color(0xFF33445F);
  }

  /// Get secondary text color (muted)
  static Color getSecondaryTextColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFB0B9C8)
        : const Color(0xFF5E6B82);
  }

  /// Get card background color
  static Color getCardColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF121A24)
        : Colors.white;
  }

  /// Get subtle background color (for containers)
  static Color getSubtleBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0F1722)
        : const Color(0xFFF3F8FF);
  }

  /// Get border color
  static Color getBorderColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF1F2937)
        : const Color(0xFFE2E7F0);
  }

  /// Get divider color
  static Color getDividerColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF2A3647)
        : const Color(0xFFE7F0FF);
  }

  /// Get disabled color
  static Color getDisabledColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF444C58)
        : const Color(0xFFF2F6FF);
  }

  /// Get route map background color (light background for map)
  static Color getRouteMapBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF0C1118)
        : const Color(0xFFF4FAF6);
  }

  /// Get color based on status (arrived/on-time/delayed)
  static Color getStatusColor(BuildContext context, String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (status == 'arrived') {
      return isDark ? const Color(0xFF4FAB96) : const Color(0xFF1C7A47);
    } else if (status == 'ontime') {
      return isDark ? const Color(0xFF6BA3E5) : const Color(0xFF0A4FB5);
    } else {
      // delayed
      return isDark ? const Color(0xFFEA9456) : const Color(0xFFE17900);
    }
  }

  /// Get accent color for list items
  static Color getAccentColor(BuildContext context, String type) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (type == 'green') {
      return isDark ? const Color(0xFF4FAB96) : const Color(0xFF0B5A25);
    } else if (type == 'blue') {
      return isDark ? const Color(0xFF6BA3E5) : const Color(0xFF164B9D);
    } else {
      // orange/secondary
      return isDark ? const Color(0xFFFF8A70) : const Color(0xFFB63519);
    }
  }

  /// Get semi-transparent overlay color
  static Color getOverlayColor(BuildContext context, double opacity) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.black.withValues(alpha: opacity)
        : Colors.white.withValues(alpha: opacity);
  }
}
