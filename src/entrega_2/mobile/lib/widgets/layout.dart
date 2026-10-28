import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';
import 'buttons.dart';

// ---------------------------------------------------------- Status bar

/// Ícones da barra de status: claros nas telas verdes, escuros nas demais.
class StatusBarStyle extends StatelessWidget {
  const StatusBarStyle({super.key, required this.light, required this.child});

  final bool light;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = light ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: base.copyWith(statusBarColor: Colors.transparent),
      child: child,
    );
  }
}

// ------------------------------------------------------------ Navegação

/// Volta para a tela anterior; se não houver, vai para [fallback].
void goBack(BuildContext context, String fallback) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

// --------------------------------------------------------------- AppBarX

/// Barra superior de 56 com botão voltar 40×40, título `title/l` e ação opcional.
class AppBarX extends StatelessWidget {
  const AppBarX({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          spacing: 4,
          children: [
            CircleIconButton(
              icon: AppIcons.arrowLeft,
              onTap: onBack,
              tooltip: 'Voltar',
            ),
            Expanded(
              child: Text(
                title,
                style: AppText.titleL,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------- Rolagem com Spacer

/// Conteúdo rolável que ocupa pelo menos a altura disponível, permitindo
/// `Spacer` para empurrar o botão principal para o rodapé.
class ScrollFill extends StatelessWidget {
  const ScrollFill({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - padding.vertical).clamp(
              0,
              double.infinity,
            ),
          ),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}

/// Tela empilhada padrão: fundo `bg/app`, AppBarX e corpo rolável.
class StackedScreen extends StatelessWidget {
  const StackedScreen({
    super.key,
    required this.title,
    required this.onBack,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 16),
    this.gap = 12,
    this.trailing,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final String title;
  final VoidCallback onBack;
  final List<Widget> children;
  final EdgeInsets padding;
  final double gap;
  final Widget? trailing;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return StatusBarStyle(
      light: false,
      child: Scaffold(
        backgroundColor: AppColors.bgApp,
        body: SafeArea(
          child: Column(
            children: [
              AppBarX(title: title, onBack: onBack, trailing: trailing),
              Expanded(
                child: ScrollFill(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: crossAxisAlignment,
                    spacing: gap,
                    children: children,
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

// ----------------------------------------------------------- Cartões

/// Cartão branco com sombra `shadow/card`.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppRadius.r20,
    this.color = AppColors.bgSurface,
    this.border,
    this.shadow = AppShadows.card,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadow),
      child: Material(
        color: color,
        borderRadius: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: border == null
                ? null
                : BoxDecoration(borderRadius: shape, border: border),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// SectionCard: superfície, raio 20, padding 16, título `title/m` opcional.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.titleStyle,
    required this.children,
    this.gap = 14,
    this.padding = const EdgeInsets.all(16),
    this.border,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final String? title;
  final TextStyle? titleStyle;
  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;
  final BoxBorder? border;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: padding,
      border: border,
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        spacing: gap,
        children: [
          if (title != null) Text(title!, style: titleStyle ?? AppText.titleM),
          ...children,
        ],
      ),
    );
  }
}

/// Quadrado 40 (raio 12) ou círculo, com ícone centralizado.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.iconSize = 20,
    this.circle = false,
    this.background = AppColors.bgBrandSoft,
    this.color = AppColors.iconBrand,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final bool circle;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(AppRadius.r12),
      ),
      child: Icon(icon, size: iconSize, color: color),
    );
  }
}

enum InfoTone { brandSoft, warning }

/// Caixa informativa: ícone 20 + título `label/l` + texto `body/s`.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.icon,
    this.title,
    required this.body,
    this.tone = InfoTone.brandSoft,
    this.bodyColor,
  });

  final IconData icon;
  final String? title;
  final String body;
  final InfoTone tone;

  /// Cor do texto, quando difere do padrão do tom.
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    final warning = tone == InfoTone.warning;
    final bg = warning ? AppColors.bgWarningSoft : AppColors.bgAccentSoft;
    final titleColor = warning ? AppColors.textWarning : AppColors.textBrand;
    final bodyColor =
        this.bodyColor ??
        (warning ? AppColors.textWarning : AppColors.textSecondary);
    final iconColor = warning ? AppColors.textWarning : AppColors.iconBrand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.r16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(icon, size: 20, color: iconColor),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                if (title != null)
                  Text(title!, style: AppText.labelL.c(titleColor)),
                Text(body, style: AppText.bodyS.c(bodyColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nota de rodapé: ícone 16 + texto `body/s` `text/secondary`.
class NoteRow extends StatelessWidget {
  const NoteRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Icon(icon, size: 16, color: AppColors.iconDefault),
        Expanded(
          child: Text(text, style: AppText.bodyS.c(AppColors.textSecondary)),
        ),
      ],
    );
  }
}

/// Gira o filho sem parar (ícone `refresh-cw` de "em andamento").
class Spinning extends StatefulWidget {
  const Spinning({super.key, required this.child});

  final Widget child;

  @override
  State<Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<Spinning>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      RotationTransition(turns: _spin, child: widget.child);
}

/// Avatar circular com inicial.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.letter,
    required this.size,
    required this.style,
    this.background = AppColors.bgBrand,
    this.image,
  });

  final String letter;
  final double size;
  final TextStyle style;
  final Color background;

  /// Foto de perfil; quando houver, substitui a inicial.
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        image: image == null
            ? null
            : DecorationImage(image: image!, fit: BoxFit.cover),
      ),
      child: image == null ? Text(letter, style: style) : null,
    );
  }
}
