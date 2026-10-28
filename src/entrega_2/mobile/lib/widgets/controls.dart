import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';

// ------------------------------------------------------------------- Chip

/// Chip em pílula. Normal: superfície + borda; selecionado: `bg/brand`.
class AppChip extends StatelessWidget {
  const AppChip(
    this.label, {
    super.key,
    this.selected = false,
    this.onTap,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Variante compacta (altura 32) — filtros do Detalhe da sessão.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.bgBrand : AppColors.bgSurface,
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : const BorderSide(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 32 : 36),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 6 : 8,
          ),
          // Largura do texto (não estica dentro de um Wrap), centralizado
          // na altura mínima.
          child: Align(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              label,
              style: AppText.labelL.c(
                selected ? AppColors.textOnBrand : AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Linha de chips (gap 8) com rolagem horizontal se não couber.
class ChipBar extends StatelessWidget {
  const ChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
    this.gap = 8,
    this.compact = false,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final EdgeInsets padding;
  final double gap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        spacing: gap,
        children: [
          for (var i = 0; i < labels.length; i++)
            AppChip(
              labels[i],
              selected: i == selected,
              compact: compact,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Badge

enum BadgeTone { neutral, brand, accent, warning, error }

class AppBadge extends StatelessWidget {
  const AppBadge(this.label, {super.key, this.tone = BadgeTone.neutral});

  final String label;
  final BadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      BadgeTone.neutral => (AppColors.bgSurfaceMuted, AppColors.textSecondary),
      BadgeTone.brand => (AppColors.bgBrandSoft, AppColors.textBrand),
      BadgeTone.accent => (AppColors.bgAccent, AppColors.textOnAccent),
      BadgeTone.warning => (AppColors.bgWarningSoft, AppColors.textWarning),
      BadgeTone.error => (AppColors.bgErrorSoft, AppColors.textError),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: AppText.labelM.c(fg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// -------------------------------------------------------------- Segmented

/// Controle de dois itens (342×48, pílula).
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.left,
    required this.right,
    required this.leftActive,
    this.onLeft,
    this.onRight,
  });

  final String left;
  final String right;
  final bool leftActive;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, bool active, VoidCallback? onTap) => Expanded(
      child: Material(
        color: active ? AppColors.bgBrand : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: active ? null : onTap,
          child: SizedBox(
            height: 40,
            child: Center(
              child: Text(
                label,
                style: AppText.labelL.c(
                  active ? AppColors.textOnBrand : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSurfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        children: [
          item(left, leftActive, onLeft),
          item(right, !leftActive, onRight),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Switch

/// Switch 52×32 com bolinha branca de 24.
class AppSwitch extends StatelessWidget {
  const AppSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 52,
          height: 32,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: value ? AppColors.bgBrand : AppColors.bgSurfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: AppColors.bgSurface,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- Checkbox

/// Checkbox 24×24 (raio 8). Marcado: `bg/brand` com `check` 16 branco.
class AppCheckbox extends StatelessWidget {
  const AppCheckbox({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: value ? AppColors.bgBrand : AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.r8),
          border: value
              ? null
              : Border.all(color: AppColors.borderStrong, width: 1.5),
        ),
        child: value
            ? const Icon(AppIcons.check, size: 16, color: AppColors.iconOnBrand)
            : null,
      ),
    );
  }
}

// ----------------------------------------------------------------- DayDot

/// Círculo de dia da semana. Mostra a letra, ou um `check` quando
/// [showCheck] e ativo (Dashboard).
class DayDot extends StatelessWidget {
  const DayDot({
    super.key,
    required this.letter,
    required this.active,
    this.size = 38,
    this.showCheck = false,
    this.onTap,
  });

  final String letter;
  final bool active;
  final double size;
  final bool showCheck;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? AppColors.bgBrand : AppColors.bgSurfaceMuted,
        ),
        child: showCheck
            ? (active
                  ? const Icon(
                      AppIcons.check,
                      size: 18,
                      color: AppColors.iconOnBrand,
                    )
                  : null)
            : Text(
                letter,
                style: AppText.labelL.c(
                  active ? AppColors.textOnBrand : AppColors.textSecondary,
                ),
              ),
      ),
    );
  }
}

/// Letras dos dias da semana, de domingo a sábado.
const kWeekLetters = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
