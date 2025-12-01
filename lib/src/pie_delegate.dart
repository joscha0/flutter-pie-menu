import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pie_menu/src/pie_button.dart';
import 'package:pie_menu/src/pie_canvas.dart';
import 'package:pie_menu/src/pie_menu.dart';
import 'package:pie_menu/src/pie_theme.dart';
import 'package:vector_math/vector_math.dart' hide Matrix4;

/// Customized [FlowDelegate] to size and position pie actions efficiently.
class PieDelegate extends FlowDelegate {
  PieDelegate({
    required this.bounceAnimation,
    required this.pointerOffset,
    required this.canvasOffset,
    required this.baseAngle,
    required this.angleDiff,
    required this.theme,
    required this.actionCount,
    required this.shouldReverseOrder,
  }) : super(repaint: bounceAnimation);

  /// Bouncing animation for the buttons.
  final Animation bounceAnimation;

  /// Offset of the widget displayed in the center of the [PieMenu].
  final Offset pointerOffset;

  /// Offset of the [PieCanvas].
  final Offset canvasOffset;

  /// Angle of the first [PieButton] in degrees.
  final double baseAngle;

  /// Angle difference between the [PieButton]s in degrees.
  final double angleDiff;

  /// Theme to use for the [PieMenu].
  final PieTheme theme;

  /// Number of actions in the menu.
  final int actionCount;

  /// Whether to reverse the order of actions for consistent visual ordering.
  final bool shouldReverseOrder;

  @override
  bool shouldRepaint(PieDelegate oldDelegate) {
    return bounceAnimation != oldDelegate.bounceAnimation;
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final dx = pointerOffset.dx - canvasOffset.dx;
    final dy = pointerOffset.dy - canvasOffset.dy;
    final count = context.childCount;

    for (var i = 0; i < count; ++i) {
      final size = context.getChildSize(i)!;
      // i == 0 is the center pointer, actions start at i == 1
      final actionIndex = i - 1;
      final effectiveIndex =
          shouldReverseOrder ? (actionCount - 1 - actionIndex) : actionIndex;
      final angleInRadians =
          radians(baseAngle - theme.angleOffset - angleDiff * effectiveIndex);
      if (i == 0) {
        context.paintChild(
          i,
          transform: Matrix4.translationValues(
            dx - size.width / 2,
            dy - size.height / 2,
            0,
          ),
        );
      } else {
        context.paintChild(
          i,
          transform: Matrix4.translationValues(
            dx -
                size.width / 2 +
                theme.radius * cos(angleInRadians) * bounceAnimation.value,
            dy -
                size.height / 2 -
                theme.radius * sin(angleInRadians) * bounceAnimation.value,
            0,
          ),
        );
      }
    }
  }

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) {
    return BoxConstraints.tight(
      i == 0
          ? Size.square(theme.pointerSize)
          : Size(theme.buttonWidth, theme.buttonHeight),
    );
  }
}
