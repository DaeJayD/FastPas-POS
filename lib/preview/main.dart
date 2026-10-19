import 'package:flutter/material.dart';
import '../core/fastpas_theme.dart';
import '../pos/product_home_screen.dart';
import 'sample_catalog.dart';

/// UI-only entry point: no Supabase initialization or database access.
void main() => runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FastPas POS · UI preview',
      theme: Volt.theme,
      builder: (context, child) =>
          LayoutBuilder(builder: (context, constraints) {
        final layout = Uri.base.queryParameters['layout'];
        final requestedWidth = layout == 'phone'
            ? 390.0
            : layout == 'tablet'
                ? 1024.0
                : constraints.maxWidth;
        final width = requestedWidth.clamp(0.0, constraints.maxWidth);
        return ColoredBox(
          color: Volt.line,
          child: Center(
              child: SizedBox(
            width: width,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(size: Size(width, constraints.maxHeight)),
              child: child!,
            ),
          )),
        );
      }),
      home: ProductHomeScreen(
        fullName: 'Alex Santos',
        role: 'owner',
        userId: 'preview',
        location: 'Main Branch',
        source: SampleCatalog(),
      ),
    ));
