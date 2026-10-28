import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';

/// Campo de formulário: rótulo `label/m` + caixa 52 (raio 12) + ajuda opcional.
/// Foco: borda 2 `border/brand`. Erro: borda 2 `border/error`.
class AppField extends StatefulWidget {
  const AppField({
    super.key,
    this.label,
    this.initialValue = '',
    this.placeholder,
    this.leadingIcon,
    this.helper,
    this.error = false,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.controller,
    this.inputFormatters,
    this.readOnly = false,
    this.onTap,
  });

  final String? label;
  final String initialValue;
  final String? placeholder;
  final IconData? leadingIcon;
  final String? helper;
  final bool error;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  /// Controlador externo (quando a tela precisa trocar o valor, ex.: data).
  final TextEditingController? controller;
  final List<TextInputFormatter>? inputFormatters;

  /// Só leitura: o toque chama [onTap] (ex.: abrir o seletor de data).
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  State<AppField> createState() => _AppFieldState();
}

class _AppFieldState extends State<AppField> {
  late final _ownController = widget.controller == null
      ? TextEditingController(text: widget.initialValue)
      : null;
  TextEditingController get _controller => widget.controller ?? _ownController!;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ownController?.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final border = widget.error
        ? Border.all(color: AppColors.borderError, width: 2)
        : focused
        ? Border.all(color: AppColors.borderBrand, width: 2)
        : Border.all(color: AppColors.borderDefault);

    final box = GestureDetector(
      onTap: widget.readOnly ? widget.onTap : _focus.requestFocus,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.r12),
          border: border,
        ),
        child: Row(
          spacing: 12,
          children: [
            if (widget.leadingIcon != null)
              Icon(widget.leadingIcon, size: 20, color: AppColors.iconDefault),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                obscureText: widget.obscure,
                obscuringCharacter: '•',
                keyboardType: widget.keyboardType,
                inputFormatters: widget.inputFormatters,
                readOnly: widget.readOnly,
                onTap: widget.onTap,
                onChanged: widget.onChanged,
                style: AppText.bodyL,
                cursorColor: AppColors.borderBrand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: widget.placeholder,
                  hintStyle: AppText.bodyL.c(AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.label == null && widget.helper == null) return box;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        if (widget.label != null)
          Text(widget.label!, style: AppText.labelM.c(AppColors.textSecondary)),
        box,
        if (widget.helper != null)
          Text(
            widget.helper!,
            style: AppText.bodyS.c(
              widget.error ? AppColors.textError : AppColors.textSecondary,
            ),
          ),
      ],
    );
  }
}
