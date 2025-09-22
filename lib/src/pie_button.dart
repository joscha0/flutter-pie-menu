import 'dart:math';

import 'package:flutter/material.dart';
import 'package:pie_menu/src/pie_action.dart';
import 'package:pie_menu/src/pie_button_theme.dart';
import 'package:pie_menu/src/pie_canvas.dart';
import 'package:pie_menu/src/pie_menu.dart';
import 'package:pie_menu/src/pie_provider.dart';
import 'package:pie_menu/src/pie_theme.dart';

/// Displays [PieAction]s of the [PieMenu] on the [PieCanvas].
class PieButton extends StatefulWidget {
  /// Creates a [PieButton] specialized for a [PieAction].
  const PieButton({
    super.key,
    required this.theme,
    required this.action,
    required this.hovered,
    required this.angle,
  });

  /// Theme of the current [PieMenu].
  final PieTheme theme;

  /// Action to display.
  final PieAction action;

  /// Whether this button is currently hovered.
  final bool hovered;

  /// Display angle of the button in radians.
  final double angle;

  @override
  State<PieButton> createState() => _PieButtonState();
}

class _PieButtonState extends State<PieButton>
    with SingleTickerProviderStateMixin {
  /// Controls [_scaleAnimation].
  late final _scaleController = AnimationController(
    duration: Duration(
      milliseconds: _theme.pieBounceDuration.inMilliseconds ~/ 2,
    ),
    vsync: this,
  );

  /// Fade animation for the button.
  late final _scaleAnimation = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(
    CurvedAnimation(
      parent: _scaleController,
      curve: Curves.ease,
    ),
  );

  /// Whether the menu was open in the previous rebuild.
  var _previouslyOpen = false;

  /// Action to display.
  PieAction get _action => widget.action;

  /// Button theme to use for idle state.
  PieButtonTheme get _buttonTheme {
    return _action.buttonTheme ?? _theme.buttonTheme;
  }

  /// Button theme to use for hovered state.
  PieButtonTheme get _buttonThemeHovered {
    return _action.buttonThemeHovered ?? _theme.buttonThemeHovered;
  }

  /// Current shared state.
  PieState get _state => PieNotifier.of(context).state;

  /// Theme of the current [PieMenu].
  ///
  /// If the [PieMenu] does not have a theme, [PieCanvas] theme is used.
  PieTheme get _theme => widget.theme;

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_previouslyOpen && _state.menuOpen) {
      _scaleController.forward(from: 0);
    }

    _previouslyOpen = _state.menuOpen;

    return OverflowBox(
      maxHeight: (_theme.buttonHeight) * 2,
      maxWidth: (_theme.buttonWidth) * 2,
      child: AnimatedScale(
        scale: widget.hovered ? 1.2 : 1,
        duration: _theme.hoverDuration,
        curve: Curves.ease,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: child,
            );
          },
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _theme.hoverDuration,
                curve: Curves.ease,
                top: widget.hovered
                    ? _theme.buttonHeight / 2 -
                        sin(widget.angle) * _theme.hoverDisplacement
                    : (_theme.buttonHeight) / 2,
                right: widget.hovered
                    ? (_theme.buttonWidth) / 2 -
                        cos(widget.angle) * _theme.hoverDisplacement
                    : (_theme.buttonWidth) / 2,
                child: SizedBox(
                  height: _theme.buttonHeight,
                  width: _theme.buttonWidth,
                  child: Center(
                    child:
                        _action.builder?.call(widget.hovered) ?? _action.child!,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
