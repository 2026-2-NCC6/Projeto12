import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_text.dart';
import '../theme/app_tokens.dart';

enum AppTab { treinos, sessao, historico, ranking, perfil }

/// Barra inferior de 5 abas (altura 80 + área segura do sistema).
class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.active, required this.onTap});

  final AppTab active;
  final ValueChanged<AppTab> onTap;

  static const _items = [
    (AppTab.treinos, AppIcons.target, 'Treinos'),
    (AppTab.sessao, AppIcons.play, 'Sessão'),
    (AppTab.historico, AppIcons.barChart, 'Histórico'),
    (AppTab.ranking, AppIcons.trophy, 'Ranking'),
    (AppTab.perfil, AppIcons.user, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
            child: Row(
              children: [
                for (final (tab, icon, label) in _items)
                  Expanded(
                    child: _NavItem(
                      icon: icon,
                      label: label,
                      active: tab == active,
                      onTap: () => onTap(tab),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.textBrand : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            Container(
              width: 64,
              height: 32,
              decoration: BoxDecoration(
                color: active ? AppColors.bgBrandSoft : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            ExcludeSemantics(
              child: Text(
                label,
                style: AppText.labelM.c(color),
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
