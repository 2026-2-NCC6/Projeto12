import 'package:flutter/material.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';
import 'controls.dart';
import 'layout.dart';

// -------------------------------------------------------------- DrillCard

class DrillCard extends StatelessWidget {
  const DrillCard({
    super.key,
    required this.drill,
    this.selected = false,
    this.onTap,
  });

  final Drill drill;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (badge, tone) = selected
        ? ('Selecionado', BadgeTone.brand)
        : drill.tipo == DrillType.catalogo
        ? ('Catálogo', BadgeTone.neutral)
        : ('Pessoal', BadgeTone.accent);

    Widget meta(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        Icon(icon, size: 16, color: AppColors.iconDefault),
        Text(text, style: AppText.labelM.c(AppColors.textSecondary)),
      ],
    );

    return SurfaceCard(
      onTap: onTap,
      color: selected ? AppColors.bgBrandSoft : AppColors.bgSurface,
      border: selected
          ? Border.all(color: AppColors.borderBrand, width: 2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(child: Text(drill.titulo, style: AppText.titleM)),
              AppBadge(badge, tone: tone),
            ],
          ),
          Text(
            drill.descricao,
            style: AppText.bodyS.c(AppColors.textSecondary),
          ),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              meta(AppIcons.target, '${drill.lances} lances'),
              meta(AppIcons.clock, 'Sessão: ${fmtDuracaoMs(drill.duracaoMs)}'),
              meta(AppIcons.flame, drill.nivel.label),
              meta(
                AppIcons.timer,
                'Intervalo entre os lances: ${fmtSegundos(drill.intervaloExatoMs)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ SessionCard

class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.session, this.onTap});

  final Session session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 52,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.bgBrandSoft,
              borderRadius: BorderRadius.circular(AppRadius.r16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  twoDigits(session.dia),
                  style: AppText.titleL.c(AppColors.textBrand),
                ),
                Text(session.mes, style: AppText.labelS.c(AppColors.textBrand)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.drillTitulo,
                  style: AppText.titleM,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${session.lances} lances · ${session.precisao}% precisão',
                  style: AppText.bodyS.c(AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 4,
            children: [
              Text(
                fmtInt(session.pontos),
                style: AppText.titleM.c(AppColors.textBrand),
              ),
              session.sincronizada
                  ? const AppBadge('Sincronizado', tone: BadgeTone.accent)
                  : const AppBadge('Pendente', tone: BadgeTone.warning),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- ShotRow

class ShotRow extends StatelessWidget {
  const ShotRow({super.key, required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context) {
    final (bg, icon, color) = switch (shot.resultado) {
      ShotResult.acerto => (
        AppColors.bgAccentSoft,
        AppIcons.check,
        AppColors.textBrand,
      ),
      ShotResult.erro => (
        AppColors.bgErrorSoft,
        AppIcons.x,
        AppColors.textError,
      ),
      ShotResult.ko => (
        AppColors.bgWarningSoft,
        AppIcons.zap,
        AppColors.textWarning,
      ),
    };
    final detalhe = switch (shot.resultado) {
      _ when shot.g == null => 'sem impacto registrado',
      ShotResult.ko => '${fmtDec(shot.g!)} g · derrubou o boneco',
      _ => '${fmtDec(shot.g!)} g',
    };
    return SurfaceCard(
      radius: AppRadius.r16,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        spacing: 12,
        children: [
          IconBadge(icon: icon, circle: true, background: bg, color: color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lance ${twoDigits(shot.n)} · ${shot.forca}',
                  style: AppText.titleM,
                ),
                Text(detalhe, style: AppText.bodyS.c(AppColors.textSecondary)),
              ],
            ),
          ),
          Text(fmtPontos(shot.pontos), style: AppText.titleM.c(color)),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- StatCard

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          IconBadge(icon: icon, size: 36, circle: true),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: AppText.headlineM),
          ),
          Text(
            label,
            style: AppText.bodyS.c(AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- RankRow

class RankRow extends StatelessWidget {
  const RankRow({super.key, required this.posicao, required this.entry});

  final int posicao;
  final RankEntry entry;

  @override
  Widget build(BuildContext context) {
    final voce = entry.voce;
    return SurfaceCard(
      radius: AppRadius.r16,
      color: voce ? AppColors.bgBrandSoft : AppColors.bgSurface,
      shadow: voce ? null : AppShadows.card,
      border: voce
          ? Border.all(color: AppColors.borderBrand, width: 1.5)
          : null,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: voce ? 12 : 12),
      child: Row(
        spacing: 12,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$posicao',
              style: AppText.titleM.c(AppColors.textSecondary),
            ),
          ),
          Avatar(
            letter: entry.inicial,
            size: 40,
            background: voce ? AppColors.bgBrand : AppColors.bgTertiarySoft,
            style: AppText.titleM.c(
              voce ? AppColors.textOnBrand : AppColors.textBrand,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.apelido,
                  style: AppText.titleM,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.detalhe != null)
                  Text(
                    entry.detalhe!,
                    style: AppText.bodyS.c(AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Text(entry.valor, style: AppText.titleM.c(AppColors.textBrand)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ SettingsRow

/// Linha de configuração: IconBadge + título/subtítulo + `chevron-right`.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          spacing: 12,
          children: [
            IconBadge(icon: icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.titleM),
                  Text(
                    subtitle,
                    style: AppText.bodyS.c(AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(
              AppIcons.chevronRight,
              size: 20,
              color: AppColors.iconDefault,
            ),
          ],
        ),
      ),
    );
  }
}

/// Linha com IconBadge + título/subtítulo + Switch (cartões de parâmetros).
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData? icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 12,
      children: [
        if (icon != null) IconBadge(icon: icon!),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.titleM),
              Text(subtitle, style: AppText.bodyS.c(AppColors.textSecondary)),
            ],
          ),
        ),
        AppSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}

// -------------------------------------------------------------- SliderRow

class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final String valueText;

  /// Posição do controle, de 0 a 1.
  final double fraction;
  final ValueChanged<double> onChanged;

  /// Quantidade de passos (ex.: 10 para 0–10 s de 1 em 1).
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppText.labelL)),
            Text(valueText, style: AppText.titleM.c(AppColors.textBrand)),
          ],
        ),
        SizedBox(
          height: 24,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: AppColors.bgBrand,
              inactiveTrackColor: AppColors.bgSurfaceMuted,
              thumbShape: const _RingThumb(),
              overlayShape: SliderComponentShape.noOverlay,
              trackShape: const _FullWidthTrack(),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: fraction.clamp(0, 1),
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Trilho sem margens laterais (a bolinha encosta nas bordas do cartão).
class _FullWidthTrack extends RoundedRectSliderTrackShape {
  const _FullWidthTrack();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final h = sliderTheme.trackHeight ?? 6;
    final top = offset.dy + (parentBox.size.height - h) / 2;
    return Rect.fromLTWH(offset.dx + 12, top, parentBox.size.width - 24, h);
  }
}

/// Bolinha 24 `bg/brand` com borda 3 `bg/surface`.
class _RingThumb extends SliderComponentShape {
  const _RingThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: 12)),
      const Color(0x40000000),
      2,
      false,
    );
    canvas.drawCircle(center, 12, Paint()..color = AppColors.bgSurface);
    canvas.drawCircle(center, 9, Paint()..color = AppColors.bgBrand);
  }
}

// --------------------------------------------------------- SessionTimeRow

/// Linha "Tempo da sessão" dos parâmetros de treino: separador + IconBadge
/// `clock` + "20 lances × 3 s" e o total (lances × intervalo) à direita.
class SessionTimeRow extends StatelessWidget {
  const SessionTimeRow({
    super.key,
    required this.lances,
    required this.intervaloS,
  });

  final int lances;
  final int intervaloS;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 16,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
        Row(
          spacing: 12,
          children: [
            const IconBadge(icon: AppIcons.clock, circle: true),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tempo da sessão', style: AppText.labelL),
                  Text(
                    '$lances lances × $intervaloS s',
                    style: AppText.bodyS.c(AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              fmtDuracao(lances * intervaloS),
              style: AppText.titleL.c(AppColors.textBrand),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------- DeviceCard

/// Cartão de dispositivo conectado (Sessão · Seleção e Perfil).
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badge,
    this.iconBackground = AppColors.bgBrand,
    this.iconColor = AppColors.iconOnBrand,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color iconBackground;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: AppRadius.r16,
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      child: Row(
        spacing: 12,
        children: [
          IconBadge(
            icon: AppIcons.bluetoothConnected,
            circle: true,
            background: iconBackground,
            color: iconColor,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.titleM),
                Text(subtitle, style: AppText.bodyS.c(AppColors.textSecondary)),
              ],
            ),
          ),
          AppBadge(badge, tone: BadgeTone.accent),
        ],
      ),
    );
  }
}
