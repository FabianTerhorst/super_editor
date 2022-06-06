import 'dart:collection';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Widget that reports un-handled key presses, allowing the client to
/// handle those key presses.
///
/// Without a [focusNode], the [keyHandler] is always given the opportunity
/// to respond to un-handled key presses. When a [focusNode] is present, the
/// [keyHandler] is only called when the [focusNode] has focus.
class UnhandledKeyPresses extends StatefulWidget {
  const UnhandledKeyPresses({
    Key? key,
    this.focusNode,
    required this.keyHandler,
    required this.child,
  }) : super(key: key);

  /// [FocusNode] that controls when [keyHandler] receives key events.
  ///
  /// If a [focusNode] is provided, [keyHandler] is only called when
  /// [focusNode] has focus.
  final FocusNode? focusNode;

  /// [KeyMessageHandler] that's called for every un-handled key event,
  /// depending on whether [focusNode] has focus.
  final KeyMessageHandler keyHandler;

  final Widget child;

  @override
  State<UnhandledKeyPresses> createState() => _UnhandledKeyPressesState();
}

class _UnhandledKeyPressesState extends State<UnhandledKeyPresses> {
  @override
  void initState() {
    super.initState();

    SuperEditorGlobalKeyHandler.instance.addKeyHandler(_onKey);
  }

  @override
  void dispose() {
    SuperEditorGlobalKeyHandler.instance.removeKeyHandler(_onKey);

    super.dispose();
  }

  bool _onKey(KeyMessage keyMessage) {
    if (widget.focusNode == null || widget.focusNode!.hasFocus) {
      return widget.keyHandler(keyMessage);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A global Flutter key handler that reports otherwise un-handled key events.
///
/// Typically, key events bubble up from descendants to ancestors. A descendant
/// decides whether or not to respond to a key event. If a descendant chooses not
/// to respond, then the event bubbles up.
///
/// The bubble-up protocol doesn't work for document editing with app shortcuts.
/// Imagine an app where pressing `tab` should move focus. That app includes a
/// document editor. The app wants the `tab` shortcut to run instead of the
/// document editor inserting a tab into the document. This use-case isn't supported
/// by the bubble-up protocol because the document doesn't know if there's an
/// ancestor shortcut or not, so the document automatically inserts a tab, and the
/// app is unable to move the focus.
///
/// In Super Editor, instead of responding to key presses within the normal bubble-up
/// protocol, a document or text field widget should register a key handler with
/// [SuperEditorGlobalKeyHandler]. By registering with [SuperEditorGlobalKeyHandler],
/// all other app key handlers will run before the document or text field's handlers,
/// which gives all shortcuts an opportunity to run before the document or text field
/// chooses to respond.
class SuperEditorGlobalKeyHandler {
  static SuperEditorGlobalKeyHandler? _instance;
  static SuperEditorGlobalKeyHandler get instance {
    if (_instance == null) {
      _instance = SuperEditorGlobalKeyHandler._();
      final KeyMessageHandler? existingKeyHandler = ServicesBinding.instance.keyEventManager.keyMessageHandler;
      ServicesBinding.instance.keyEventManager.keyMessageHandler = _instance!._createKeyHandler(existingKeyHandler!);
    }
    return _instance!;
  }

  SuperEditorGlobalKeyHandler._();

  // The key handlers is a `LinkedHashSet` so that we get `Set`
  // de-duplication, and also retain insertion order.
  // ignore: prefer_collection_literals
  final _appKeyHandlers = LinkedHashSet<KeyMessageHandler>();

  /// Adds the given [handler] to a global chain of responsibility that
  /// is given the opportunity to respond to otherwise unhandled key events.
  void addKeyHandler(KeyMessageHandler handler) {
    _appKeyHandlers.add(handler);
  }

  /// Removes the given [handler], which was previously added with [addKeyHandler].
  void removeKeyHandler(KeyMessageHandler handler) {
    _appKeyHandlers.remove(handler);
  }

  /// Wraps Flutter's existing key handler with a decorator that handles otherwise
  /// un-handled key events.
  KeyMessageHandler _createKeyHandler(KeyMessageHandler existingKeyHandler) {
    return (KeyMessage message) {
      if (existingKeyHandler(message)) {
        // The key was handled by some other part of the app,
        // e.g., the shortcut system.
        //
        // Why do we do this? See:
        // https://github.com/superlistapp/super_editor/issues/591
        // https://github.com/flutter/flutter/pull/105280
        // https://api.flutter.dev/flutter/services/KeyEventManager/keyMessageHandler.html
        return true;
      }

      // The key wasn't handled by anything else. Give our clients
      // an opportunity to respond to it.
      for (final handler in _appKeyHandlers) {
        if (handler(message)) {
          return true;
        }
      }
      return false;
    };
  }
}
