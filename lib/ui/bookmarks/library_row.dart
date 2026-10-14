import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../widgets.dart';

/// A saved title opens its detail page, without promising iframe timestamp seek.
class LibraryRow extends StatelessWidget {
  final SavedTitleRef title;
  final WatchEntry? checkpoint;
  final VoidCallback onOpen;

  const LibraryRow({
    super.key, required this.title, required this.onOpen, this.checkpoint,
  });

  @override
  Widget build(BuildContext context) {
    final entry = checkpoint;
    final episode = entry == null ? '' : <String>[
      if (entry.season != null && entry.season! > 0) 'Сезон ${entry.season}',
      if (entry.episode != null && entry.episode! > 0) 'Серия ${entry.episode}',
    ].join(' · ');
    final seconds = entry == null ? 0 : entry.positionMs ~/ 1000;
    final position = seconds > 0
        ? 'Позиция ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}'
        : 'Начало серии или позиция не сохранена';
    final date = entry?.watchedAt.toLocal();
    final savedDate = date == null ? '' :
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    return Semantics(
      button: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Poster(url: title.poster, width: 48, height: 68),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    if (entry != null) ...[
                      const SizedBox(height: 6),
                      Text(<String>[if (episode.isNotEmpty) episode, position].join('\n'),
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text('Сохранено $savedDate',
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    ] else if (title.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(title.subtitle,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 6),
                    const Text('Открыть карточку',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                )),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
