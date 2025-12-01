import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pie_menu/src/bouncing_widget.dart';
import 'package:pie_menu/src/pie_action.dart';
import 'package:pie_menu/src/pie_button.dart';
import 'package:pie_menu/src/pie_canvas.dart';
import 'package:pie_menu/src/pie_delegate.dart';
import 'package:pie_menu/src/pie_menu.dart';
import 'package:pie_menu/src/pie_provider.dart';
import 'package:pie_menu/src/pie_theme.dart';
import 'package:pie_menu/src/platform/base.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// Controls functionality and appearance of [PieCanvas].
class PieCanvasCore extends StatefulWidget {
  const PieCanvasCore({
    super.key,
    required this.onMenuToggle,
    required this.theme,
    required this.child,
  });

  final Function(bool menuOpen)? onMenuToggle;
  final PieTheme theme;
  final Widget child;

  @override
  PieCanvasCoreState createState() => PieCanvasCoreState();
}

class PieCanvasCoreState extends State<PieCanvasCore>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Controls platform-specific functionality, used to handle right-clicks.
  final _platform = BasePlatform();

  /// Controls [_buttonBounceAnimation].
  late final _buttonBounceController = AnimationController(
    duration: _theme.pieBounceDuration,
    vsync: this,
  );

  /// Bouncing animation for the [PieButton]s.
  late final _buttonBounceAnimation = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(
    CurvedAnimation(
      parent: _buttonBounceController,
      curve: Curves.elasticOut,
    ),
  );

  /// Controls [_fadeAnimation].
  late final _fadeController = AnimationController(
    duration: _theme.fadeDuration,
    vsync: this,
  );

  /// Fade animation for the canvas and current menu.
  late final _fadeAnimation = Tween(
    begin: 0.0,
    end: 1.0,
  ).animate(
    CurvedAnimation(
      parent: _fadeController,
      curve: Curves.ease,
    ),
  );

  /// Whether menu child is currently pressed.
  var _pressed = false;

  /// Whether menu child is pressed again while a menu is open.
  var _pressedAgain = false;

  /// Current pointer offset.
  var _pointerOffset = Offset.zero;

  /// Pointer offset relative to the menu.
  var _localPointerOffset = Offset.zero;

  /// Initially pressed offset.
  var _pressedOffset = Offset.zero;

  /// Actions of the current [PieMenu].
  var _actions = <PieAction>[];

  /// Starts when the pointer is down,
  /// is triggered after the delay duration specified in [PieTheme],
  /// and gets cancelled when the pointer is up.
  Timer? _attachTimer;

  /// Starts when the pointer is up,
  /// is triggered after the fade duration specified in [PieTheme],
  /// and gets cancelled when the pointer is down again.
  Timer? _detachTimer;

  /// Functional callback triggered when the current menu opens or closes.
  Function(bool menuOpen)? _onMenuToggle;

  /// Size of the screen. Used to close the menu when the screen size changes.
  var _physicalSize = PlatformDispatcher.instance.views.first.physicalSize;

  /// Theme of the current [PieMenu].
  ///
  /// If the [PieMenu] does not have a theme, [PieCanvas] theme is used.
  late var _theme = widget.theme;

  /// Stream subscription for right-clicks.
  dynamic _contextMenuSubscription;

  /// RenderBox of the current menu.
  RenderBox? _menuRenderBox;

  /// Child widget of the current menu.
  Widget? _menuChild;

  /// Bounce animation for the child widget of the current menu.
  Animation<double>? _childBounceAnimation;

  /// Tooltip widget of the currently hovered action.
  Widget? _tooltip;

  /// Controls the shared state.
  PieNotifier get _notifier => PieNotifier.of(context);

  /// Current shared state.
  PieState get _state => _notifier.state;

  /// Offset of the canvas relative to the screen.
  var _canvasOffset = Offset.zero;

  /// Offset of the menu relative to the screen.
  var _menuOffset = Offset.zero;

  /// RenderBox of the canvas.
  RenderBox? get _canvasRenderBox {
    final object = context.findRenderObject();
    return object is RenderBox && object.hasSize ? object : null;
  }

  Size get _canvasSize => _canvasRenderBox?.size ?? Size.zero;
  double get cw => _canvasSize.width;
  double get ch => _canvasSize.height;
  double get cx => _canvasOffset.dx;
  double get cy => _canvasOffset.dy;
  double get px => _pointerOffset.dx - cx;
  double get py => _pointerOffset.dy - cy;

  // Effective button dimensions
  double get _buttonW => _theme.buttonWidth;
  double get _buttonH => _theme.buttonHeight;

  /// Detect whether near edges/corners, then reduce the angle span accordingly.
  double get _maxAllowedArc {
    if (_actions.isEmpty || _actions.length == 1) return 0;
    if (_actions.length < 4) return 90;
    return 180;
  }

  double get _angleDiff {
    final customAngleDiff = _theme.customAngleDiff;
    if (customAngleDiff != null) return customAngleDiff;

    if (_actions.isEmpty || _actions.length == 1) return 0;

    final arc = _maxAllowedArc;
    return arc / (_actions.length - 1);
  }

  /// Whether the menu buttons should be rendered in reverse order.
  /// This ensures consistent visual ordering regardless of menu side.
  bool get _shouldReverseOrder {
    final margin = _theme.radius + max(_buttonW, _buttonH);
    final atRight = px > cw - margin;
    return atRight;
  }

  /// Base angle ensures the arc bends inward into the screen.
  double get _baseAngle {
    final arc = (_actions.length - 1) * _angleDiff;

    final margin = _theme.radius + max(_buttonW, _buttonH);
    final atLeft = px < margin;
    final atRight = px > cw - margin;
    final atTop = py < margin;
    final atBottom = py > ch - margin;

    // Default orientation = right
    double base = 0;

    if (atTop && !atBottom) {
      base = 270; // open downward
    } else if (atBottom && !atTop) {
      base = 90; // open upward
    }
    if (atLeft && !atRight) {
      base = 0; // open right
    } else if (atRight && !atLeft) {
      base = 180; // open left
    }
    if (atLeft && atTop) {
      base = 315; // open down-right
    } else if (atLeft && atBottom) {
      base = 45; // open up-right
    } else if (atRight && atTop) {
      base = 225; // open down-left
    } else if (atRight && atBottom) {
      base = 135; // open up-left
    }

    return base + arc / 2; // center arc around chosen base
  }

  double _getActionAngle(int index) {
    final effectiveIndex =
        _shouldReverseOrder ? (_actions.length - 1 - index) : index;
    return radians(
      _baseAngle - _theme.angleOffset - _angleDiff * effectiveIndex,
    );
  }

  Offset _getActionOffset(int index) {
    final angle = _getActionAngle(index);
    return Offset(
      _pointerOffset.dx + (_theme.radius) * cos(angle),
      _pointerOffset.dy - (_theme.radius) * sin(angle),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
      ..addObserver(this)
      ..addPostFrameCallback((_) {
        _canvasOffset =
            _canvasRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_state.menuOpen) {
        setState(() {
          _canvasOffset =
              _canvasRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
          _menuOffset =
              _menuRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _buttonBounceController.dispose();
    _fadeController.dispose();
    _attachTimer?.cancel();
    _detachTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted && _state.menuOpen) {
      final prevSize = _physicalSize;
      _physicalSize = PlatformDispatcher.instance.views.first.physicalSize;
      if (prevSize != _physicalSize) {
        _notifier.update(
          menuOpen: false,
          clearMenuKey: true,
        );
        _notifyToggleListeners(menuOpen: false);
        _detachMenu(animate: false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuRenderBox = _menuRenderBox;
    final hoveredAction = _state.hoveredAction;
    if (hoveredAction != null) {
      _tooltip = _actions[hoveredAction].tooltip;
    }

    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (_state.menuOpen) {
          setState(() {
            _menuOffset =
                _menuRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
          });
        }
        return false;
      },
      child: Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          cursor: hoveredAction != null
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: Stack(
            children: [
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) => _pointerDown(event.position),
                onPointerMove: (event) => _pointerMove(event.position),
                onPointerHover: _state.menuOpen
                    ? (event) => _pointerMove(event.position)
                    : null,
                onPointerUp: (event) => _pointerUp(event.position),
                child: IgnorePointer(
                  ignoring: _state.menuOpen,
                  child: widget.child,
                ),
              ),
              IgnorePointer(
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _fadeAnimation.value,
                      child: child,
                    );
                  },
                  child: Stack(
                    children: [
                      // Overlay
                      if (menuRenderBox != null && menuRenderBox.attached)
                        ...() {
                          switch (_theme.overlayStyle) {
                            case PieOverlayStyle.around:
                              return [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: OverlayPainter(
                                      color: _theme.effectiveOverlayColor,
                                      menuOffset: Offset(
                                        _menuOffset.dx - cx,
                                        _menuOffset.dy - cy,
                                      ),
                                      menuSize: menuRenderBox.size,
                                    ),
                                  ),
                                ),
                              ];
                            case PieOverlayStyle.behind:
                              final bounceAnimation = _childBounceAnimation;

                              return [
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: _theme.effectiveOverlayColor,
                                  ),
                                ),
                                Positioned(
                                  left: _menuOffset.dx - cx,
                                  top: _menuOffset.dy - cy,
                                  child: AnimatedOpacity(
                                    opacity: _state.menuOpen &&
                                            _state.hoveredAction != null
                                        ? _theme.childOpacityOnButtonHover
                                        : 1,
                                    duration: _theme.hoverDuration,
                                    curve: Curves.ease,
                                    child: SizedBox.fromSize(
                                      size: menuRenderBox.size,
                                      child: _theme.childBounceEnabled &&
                                              bounceAnimation != null
                                          ? BouncingWidget(
                                              theme: _theme,
                                              animation: bounceAnimation,
                                              pressedOffset:
                                                  _localPointerOffset,
                                              child: _menuChild ??
                                                  const SizedBox(),
                                            )
                                          : _menuChild,
                                    ),
                                  ),
                                ),
                              ];
                          }
                        }(),
                      // Tooltip
                      () {
                        final tooltipAlignment = _theme.tooltipCanvasAlignment;

                        Widget child = AnimatedOpacity(
                          opacity: hoveredAction != null ? 1 : 0,
                          duration: _theme.hoverDuration,
                          curve: Curves.ease,
                          child: Padding(
                            padding: _theme.tooltipPadding,
                            child: DefaultTextStyle.merge(
                              textAlign: _theme.tooltipTextAlign ??
                                  (px < cw / 2
                                      ? TextAlign.right
                                      : TextAlign.left),
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: _theme.brightness == Brightness.light
                                    ? Colors.black
                                    : Colors.white,
                              )
                                  .merge(widget.theme.tooltipTextStyle)
                                  .merge(_theme.tooltipTextStyle),
                              child: _tooltip ?? const SizedBox(),
                            ),
                          ),
                        );

                        if (_theme.tooltipUseFittedBox) {
                          child = FittedBox(child: child);
                        }

                        if (tooltipAlignment != null) {
                          return Align(
                            alignment: tooltipAlignment,
                            child: child,
                          );
                        } else {
                          return Positioned(
                            top: 0,
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Align(
                              alignment: px < cw / 2
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: child,
                            ),
                          );
                        }
                      }(),
                      // Buttons
                      Flow(
                        delegate: PieDelegate(
                          bounceAnimation: _buttonBounceAnimation,
                          pointerOffset: _pointerOffset,
                          canvasOffset: _canvasOffset,
                          baseAngle: _baseAngle,
                          angleDiff: _angleDiff,
                          theme: _theme,
                          actionCount: _actions.length,
                          shouldReverseOrder: _shouldReverseOrder,
                        ),
                        children: [
                          DecoratedBox(
                            decoration: _theme.pointerDecoration ??
                                BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _theme.pointerColor ??
                                        (_theme.brightness == Brightness.light
                                            ? Colors.black
                                                .withValues(alpha: 0.35)
                                            : Colors.white
                                                .withValues(alpha: 0.5)),
                                    width: 4,
                                  ),
                                ),
                          ),
                          for (int i = 0; i < _actions.length; i++)
                            PieButton(
                              theme: _theme,
                              action: _actions[i],
                              angle: _getActionAngle(i),
                              hovered: i == hoveredAction,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _notifyToggleListeners({required bool menuOpen}) {
    _onMenuToggle?.call(menuOpen);
    widget.onMenuToggle?.call(menuOpen);
  }

  bool _isBeyondPointerBounds(Offset offset) {
    return (_pressedOffset - offset).distance > _theme.pointerSize / 2;
  }

  void attachMenu({
    required bool rightClicked,
    required RenderBox renderBox,
    required Widget child,
    required Animation<double>? bounceAnimation,
    required Key menuKey,
    required List<PieAction> actions,
    required PieTheme theme,
    required Function(bool menuOpen)? onMenuToggle,
    required Offset? offset,
    required Alignment? menuAlignment,
    required Offset? menuDisplacement,
  }) {
    assert(
      offset != null || menuAlignment != null,
      'Offset or alignment must be provided.',
    );

    _theme = theme;
    _contextMenuSubscription = _platform.listenContextMenu(
      shouldPreventDefault: rightClicked,
    );

    _attachTimer?.cancel();
    _detachTimer?.cancel();

    if (!_pressed) {
      _pressed = true;
      menuAlignment ??= _theme.menuAlignment;
      menuDisplacement ??= _theme.menuDisplacement;

      if (menuAlignment != null) {
        _pointerOffset = renderBox.localToGlobal(
          renderBox.size.center(
            Offset(
              menuAlignment.x * renderBox.size.width / 2,
              menuAlignment.y * renderBox.size.height / 2,
            ),
          ),
        );
      } else if (offset != null) {
        _pointerOffset = offset;
      }

      _pointerOffset += menuDisplacement;
      _pressedOffset = offset ?? _pointerOffset;
      _localPointerOffset = renderBox.globalToLocal(_pointerOffset);

      _attachTimer = Timer(Duration.zero, () {
        _detachTimer?.cancel();

        _buttonBounceController.forward(from: 0);
        _fadeController.forward(from: 0);

        _menuRenderBox = renderBox;
        _menuOffset = renderBox.localToGlobal(Offset.zero);
        _menuChild = child;
        _childBounceAnimation = bounceAnimation;
        _onMenuToggle = onMenuToggle;
        _actions = actions;
        _tooltip = null;

        _notifier.update(
          menuOpen: true,
          menuKey: menuKey,
          clearHoveredAction: true,
        );
        _notifyToggleListeners(menuOpen: true);
      });
    }
  }

  void closeMenu(Key menuKey) {
    if (menuKey == _notifier.state.menuKey) {
      _detachMenu();
    }
  }

  void _detachMenu({bool animate = true}) {
    final subscription = _contextMenuSubscription;
    if (subscription is StreamSubscription) subscription.cancel();

    if (animate) {
      _fadeController.reverse();
    } else {
      _fadeController.animateTo(0, duration: Duration.zero);
    }

    _detachTimer = Timer(
      animate ? _theme.fadeDuration : Duration.zero,
      () {
        _attachTimer?.cancel();
        _pressed = false;
        _pressedAgain = false;

        _notifier.update(
          clearMenuKey: true,
          menuOpen: false,
          clearHoveredAction: true,
        );
      },
    );
  }

  void _pointerDown(Offset offset) {
    if (_state.menuOpen) {
      _pressedAgain = true;
      _pointerMove(offset);
    }
  }

  void _pointerUp(Offset offset) {
    if (_state.menuOpen) {
      if (_pressedAgain || _isBeyondPointerBounds(offset)) {
        final hoveredAction = _state.hoveredAction;
        if (hoveredAction != null) {
          _actions[hoveredAction].onSelect();
        }
        _notifier.update(menuOpen: false);
        _notifyToggleListeners(menuOpen: false);
        _detachMenu();
      }
    } else if (!_theme.regularPressShowsMenu) {
      _detachMenu();
    }
    _pressed = false;
    _pressedAgain = false;
    _pressedOffset = _pointerOffset;
  }

  void _pointerMove(Offset offset) {
    if (_state.menuOpen) {
      void hover(int? action) {
        if (_state.hoveredAction != action) {
          _notifier.update(
            hoveredAction: action,
            clearHoveredAction: action == null,
          );
        }
      }

      final withinSafeDistance = (_pressedOffset - offset).distance < 8;
      if (_pressedOffset != _pointerOffset && !withinSafeDistance) {
        _pressedOffset = _pointerOffset;
      }

      final pointerDistance = (_pointerOffset - offset).distance;

      if (withinSafeDistance ||
          pointerDistance < _theme.radius - min(_buttonW, _buttonH) * 0.5 ||
          pointerDistance > _theme.radius + max(_buttonW, _buttonH) * 0.8) {
        hover(null);
      } else {
        var closestDistance = double.infinity;
        var closestAction = 0;
        for (var i = 0; i < _actions.length; i++) {
          final actionOffset = _getActionOffset(i);
          final distance = (actionOffset - offset).distance;
          if (distance < closestDistance) {
            closestDistance = distance;
            closestAction = i;
          }
        }
        final hoverThreshold = 0.8 * max(_buttonW, _buttonH);
        hover(closestDistance < hoverThreshold ? closestAction : null);
      }
    } else if (_pressed && _isBeyondPointerBounds(offset)) {
      _detachMenu(animate: false);
    }
  }
}

class OverlayPainter extends CustomPainter {
  const OverlayPainter({
    required this.color,
    required this.menuOffset,
    required this.menuSize,
  });

  final Color color;
  final Offset menuOffset;
  final Size menuSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    final path = Path();
    path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    path.addRect(menuOffset & menuSize);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
