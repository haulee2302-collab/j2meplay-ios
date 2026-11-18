import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Ô nhập ẩn để gọi bàn phím iOS: mỗi ký tự gõ vào được chuyển thành phím gửi cho game.
class HiddenKeyboard extends StatefulWidget {
  final void Function(String ch) onChar;
  final void Function(String key) onKey;
  final VoidCallback? onClosed;
  const HiddenKeyboard({super.key, required this.onChar, required this.onKey, this.onClosed});
  @override
  State<HiddenKeyboard> createState() => HiddenKeyboardState();
}

class HiddenKeyboardState extends State<HiddenKeyboard> {
  static const _mark = '​';
  final FocusNode focus = FocusNode();
  final TextEditingController ctl = TextEditingController(text: _mark);

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (!focus.hasFocus) widget.onClosed?.call();
    });
  }

  @override
  void dispose() {
    focus.dispose();
    ctl.dispose();
    super.dispose();
  }

  void toggle() {
    if (focus.hasFocus) {
      focus.unfocus();
    } else {
      _reset();
      focus.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  void _reset() => ctl.value = const TextEditingValue(text: _mark, selection: TextSelection.collapsed(offset: 1));

  void _changed(String v) {
    if (v.isEmpty) {
      widget.onKey('BACKSPACE');
    } else if (v.length > 1) {
      for (final r in v.substring(1).runes) {
        widget.onChar(String.fromCharCode(r));
      }
    }
    _reset();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      height: 1,
      child: Opacity(
        opacity: 0.01,
        child: TextField(
          controller: ctl,
          focusNode: focus,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.send,
          onChanged: _changed,
          onSubmitted: (_) {
            widget.onKey('OK');
            focus.requestFocus();
          },
          decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
          style: const TextStyle(fontSize: 1),
        ),
      ),
    );
  }
}
