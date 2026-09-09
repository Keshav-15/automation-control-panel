import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../base/utils/constants/color_constant.dart';
import '../base/utils/constants/fontsize_constant.dart';

class PrimaryTextField extends StatefulWidget {
  final String hint;
  final FocusNode focusNode;
  final TextInputType type;
  final String? trailingIcon;
  final int? maxLength;
  final bool enabled;
  final bool isObscureText;
  final TextInputAction textInputAction;
  final List<TextInputFormatter>? textInputFormatter;
  final TextEditingController controller;
  final Function(String?)? onSaved;
  final String? Function(String?)? validateFunction;
  final Function? endIconClick;
  final Function(String)? onFieldSubmitted;
  final Function(String)? onChanged;
  final int maxLines;
  final bool autoFocus;

  const PrimaryTextField({
    super.key,
    required this.hint,
    required this.focusNode,
    required this.type,
    this.trailingIcon,
    this.isObscureText = false,
    required this.textInputAction,
    this.enabled = true,
    this.onSaved,
    this.maxLength,
    this.validateFunction,
    this.endIconClick,
    this.onFieldSubmitted,
    this.textInputFormatter,
    this.onChanged,
    required this.controller,
    this.maxLines = 1,
    this.autoFocus = false,
  });

  @override
  State<StatefulWidget> createState() => PrimaryTextFieldState();
}

class PrimaryTextFieldState extends State<PrimaryTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      autofocus: widget.autoFocus,
      controller: widget.controller,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      focusNode: widget.focusNode,
      textCapitalization: TextCapitalization.sentences,
      enabled: widget.enabled,
      style: TextStyle(
        color: widget.enabled ? primaryTextColor : Colors.grey,
        fontSize: fontSize16,
        fontWeight: fontWeightRegular,
      ),
      decoration: InputDecoration(
        labelText: widget.hint,
        counter: const Offstage(),
        contentPadding: const EdgeInsets.all(0.0),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        errorStyle: const TextStyle(color: Colors.red),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 1.0),
        ),
        errorMaxLines: 3,
        labelStyle: const TextStyle(fontSize: fontSize14, color: Colors.grey),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: primaryColor, width: 1),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 1),
        ),
        suffixIcon: widget.isObscureText ? _passwordIcon() : _suffixIconCheck(),
      ),
      maxLines: widget.maxLines,
      onFieldSubmitted: widget.onFieldSubmitted,
      validator: widget.validateFunction,
      onSaved: widget.onSaved,
      inputFormatters: widget.textInputFormatter,
      keyboardType: widget.type,
      obscureText: widget.isObscureText ? _obscureText : false,
      onChanged: widget.onChanged,
    );
  }

  GestureDetector? _suffixIconCheck() => widget.trailingIcon != null
      ? GestureDetector(
          onTap: () {
            widget.endIconClick!();
          },
          child: SizedBox(
            height: 15,
            width: 15,
            child: Image.asset(
              widget.trailingIcon!,
              color: widget.endIconClick == null ? primaryTextColor : null,
              scale: 2.7,
            ),
          ),
        )
      : null;

  InkWell _passwordIcon() => InkWell(
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    onTap: () {
      setState(() {
        _obscureText = !_obscureText;
      });
    },
    child: SizedBox(
      height: 15,
      width: 15,
      child: Icon(
        _obscureText ? Icons.visibility_off : Icons.visibility,
        color: primaryTextColor,
      ),
    ),
  );
}
