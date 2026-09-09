import 'package:flutter/material.dart';
import 'package:flutter_boilerplate/src/models/qa/project_model.dart';

/// Icons for the reserved stage tags — everything else just shows as a
/// plain text chip (see [CommandConfig.tags]).
const kStageTagIcons = {
  'prerequisite': Icons.checklist_outlined,
  'git': Icons.account_tree_outlined,
  'build': Icons.build_outlined,
  'test': Icons.science_outlined,
  'report': Icons.bar_chart_outlined,
};

/// One command row — shared by [CommandLibraryScreen] (the pool-wide "All
/// Commands" view) and [SurfaceCommandManagerScreen] (one surface + one
/// stage), so both stay visually identical.
class CommandTile extends StatelessWidget {
  final CommandConfig command;
  final List<SurfaceConfig> assignedSurfaces;
  final List<SurfaceConfig> allSurfaces;
  final bool showDragHandle;
  final bool? isInCurrentSurface; // null = no single surface context
  final VoidCallback onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback onDelete;
  final void Function(String? surfaceId) onToggleSurface;

  const CommandTile({
    super.key,
    required this.command,
    required this.assignedSurfaces,
    required this.allSurfaces,
    required this.showDragHandle,
    this.isInCurrentSurface,
    required this.onEdit,
    this.onDuplicate,
    required this.onDelete,
    required this.onToggleSurface,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isUnassigned = isInCurrentSurface == false;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isUnassigned
              ? cs.outlineVariant.withValues(alpha: 0.5)
              : cs.outlineVariant,
        ),
      ),
      color: isUnassigned ? cs.surface.withValues(alpha: 0.7) : null,
      child: ListTile(
        onTap: onEdit,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: showDragHandle
            ? const Icon(Icons.drag_handle, color: Colors.grey)
            : isInCurrentSurface == false
                ? IconButton(
                    tooltip: 'Add to this surface',
                    icon: Icon(Icons.add_circle_outline,
                        color: cs.primary, size: 20),
                    onPressed: () => onToggleSurface(null),
                  )
                : null,
        title: Row(
          children: [
            Expanded(
              child: Text(
                command.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isUnassigned ? cs.onSurfaceVariant : null,
                    ),
              ),
            ),
            // Tag badges
            ...command.tags.map((t) => _badge(
                  context,
                  t,
                  cs.surfaceContainerHighest,
                  cs.onSurfaceVariant,
                  icon: kStageTagIcons[t],
                  tooltip: kStageTagIcons.containsKey(t)
                      ? 'Pipeline stage: $t — decides when this runs'
                      : 'Tag: $t — for search/filtering only',
                )),
            // Behaviour badges
            if (command.skipIfNoSync)
              _badge(context, 'Sync', cs.primaryContainer, cs.onPrimaryContainer,
                  tooltip: 'Skipped when the surface\'s Sync toggle is off'),
            if (command.skipIfNoBuild)
              _badge(context, 'Build', cs.secondaryContainer,
                  cs.onSecondaryContainer,
                  tooltip:
                      'Skipped when the surface\'s Build+Install toggle is off'),
            if (command.detach)
              _badge(context, 'detach', cs.tertiaryContainer,
                  cs.onTertiaryContainer,
                  tooltip: 'Fire-and-forget — the pipeline moves on '
                      'immediately instead of waiting for this to finish '
                      '(e.g. opening a report)'),
            if (command.target != null)
              _badge(
                context,
                command.target == 'simulator' ? '🖥️ sim' : '📱 device',
                cs.surfaceContainerHighest,
                cs.onSurface,
                tooltip: command.target == 'simulator'
                    ? 'Only runs when the iOS target is set to Simulator'
                    : 'Only runs when the iOS target is set to Real Device',
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                command.command,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Surface assignment badges (shown in "All" tab)
            if (isInCurrentSurface == null && assignedSurfaces.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 4,
                  children: assignedSurfaces
                      .map((s) => _badge(context, '${s.icon} ${s.name}',
                          cs.primaryContainer, cs.onPrimaryContainer))
                      .toList(),
                ),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Remove from surface button (in surface tab, assigned state)
            if (isInCurrentSurface == true)
              Tooltip(
                message: 'Remove from this surface',
                child: IconButton(
                  icon: Icon(Icons.remove_circle_outline,
                      size: 18, color: cs.error),
                  onPressed: () => onToggleSurface(null),
                ),
              ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: onEdit,
            ),
            if (onDuplicate != null)
              IconButton(
                tooltip: 'Duplicate',
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: onDuplicate,
              ),
            IconButton(
              tooltip: 'Delete from library',
              icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(
    BuildContext context,
    String label,
    Color bg,
    Color fg, {
    IconData? icon,
    String? tooltip,
  }) {
    final chip = Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: fg, fontSize: 10),
          ),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip, child: chip);
  }
}
