import 'package:flutter/material.dart';

import '../../core/kodik_api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../release/title_screen.dart';
import '../widgets.dart';

/// Уведомления.
///
/// У Kodik нет ленты уведомлений, поэтому экран честно показывает недавно
/// обновлённые тайтлы в оформлении эталонного клиента.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Обновления',
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Недавно обновлённые записи каталога Kodik. '
                'Это не личные уведомления и не подтверждение выхода новых серий.',
                style:
                    TextStyle(fontSize: 13.5, color: AppColors.textTertiary)),
          ),
        ),
        Expanded(
          child: PagedScroll(
            key: const ValueKey('notifications-updated'),
            loader: (cursor) => KodikApi.instance.fetch(
              CatalogFilter(types: KodikCatalog.all, sort: CatalogSort.updated),
              cursor: cursor,
            ),
            itemBuilder: (context, title, _) => ReleaseListItem.kodik(
              title,
              onTap: () => openTitle(context, title),
            ),
            emptyText: 'Обновлений в каталоге пока нет',
          ),
        ),
      ]),
    );
  }
}
