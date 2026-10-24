import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';

enum AppButtonVariant { primary, accent, outline, danger, text }

/// Botão padrão: altura 52 (compacto 44), raio 16, ícone 20 + texto `button`.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.compact = false,
    this.dimmed = false,
    this.expand = true,
    this.iconAfter = false,
  });

  const AppButton.outline(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.compact = false,
    this.expand = true,
  }) : variant = AppButtonVariant.outline,
       dimmed = false,
       iconAfter = false;

  const AppButton.danger(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.expand = true,
  }) : variant = AppButtonVariant.danger,
       compact = false,
       dimmed = false,
       iconAfter = false;

  const AppButton.text(
    this.label, {
    super.key,
    this.onPressed,
    this.icon,
    this.expand = true,
  }) : variant = AppButtonVariant.text,
       compact = false,
       dimmed = false,
       iconAfter = false;

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool compact;

  /// Aparência de desabilitado (40%) sem bloquear o toque — usado no
  /// protótipo onde o botão "desabilitado" ainda navega.
  final bool dimmed;
  final bool expand;

  /// Ícone depois do texto (ex.: `chevron-right` em "Continuar…").
  final bool iconAfter;

  @override
  Widget build(BuildContext context) {
    final (Color? bg, Color fg, BorderSide side) = switch (variant) {
      AppButtonVariant.primary => (
        AppColors.bgBrand,
        AppColors.textOnBrand,
        BorderSide.none,
      ),
      AppButtonVariant.accent => (
        AppColors.bgAccent,
        AppColors.textOnAccent,
        BorderSide.none,
      ),
      AppButtonVariant.outline => (
        null,
        AppColors.textBrand,
        const BorderSide(color: AppColors.borderBrand, width: 1.5),
      ),
      AppButtonVariant.danger => (
        AppColors.bgError,
        AppColors.textOnBrand,
        BorderSide.none,
      ),
      AppButtonVariant.text => (null, AppColors.textBrand, BorderSide.none),
    };
    final disabled = dimmed || onPressed == null;
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: SizedBox(
        height: compact ? 44 : 52,
        width: expand ? double.infinity : null,
        child: Material(
          color: bg ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r16),
            side: side,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 24),
              // Em larguras estreitas (botões lado a lado em 360 dp), o
              // conteúdo encolhe em vez de cortar o texto.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    if (icon != null && !iconAfter)
                      Icon(icon, size: 20, color: fg),
                    Text(label, style: AppText.button.c(fg), maxLines: 1),
                    if (icon != null && iconAfter)
                      Icon(icon, size: 20, color: fg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão circular de ícone (voltar da AppBarX, lixeira etc.).
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.iconPrimary,
    this.size = 40,
    this.iconSize = 24,
    this.background,
    this.shadow,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final double iconSize;
  final Color? background;
  final List<BoxShadow>? shadow;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: shadow),
      child: Material(
        color: background ?? Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// Link de texto (`label/l` `text/brand`) tocável.
class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap, this.style});

  final String label;
  final VoidCallback onTap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: style ?? AppText.labelL.c(AppColors.textBrand),
        ),
      ),
    );
  }
}
