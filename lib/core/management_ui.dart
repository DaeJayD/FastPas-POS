import 'package:flutter/material.dart';

import 'fastpas_theme.dart';

/// A compact title that leaves room for back and refresh controls on phones.
class ManagementTitle extends StatelessWidget {
  const ManagementTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      if (subtitle != null)
        Text(
          subtitle!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Volt.muted),
        ),
    ],
  );
}

/// Related cards and form fields stack when a phone or larger text needs room.
class ManagementColumns extends StatelessWidget {
  const ManagementColumns({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final items = children
          .where((item) => item is! SizedBox)
          .map((item) => item is Flexible ? item.child : item)
          .toList();
      if (box.maxWidth < 600 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.2) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              items[i],
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: items[i]),
          ],
        ],
      );
    },
  );
}
