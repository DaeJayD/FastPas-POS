import 'package:flutter/material.dart';

import '../core/fastpas_theme.dart';
import '../pos/product_home_screen.dart';
import 'sample_catalog.dart';
import 'management_samples.dart';

/// UI-only entry point: all management requests stay in a local transport.
void main() {
  enableManagementSamples();
  runApp(const FastPasPreviewApp());
}

class FastPasPreviewApp extends StatelessWidget {
  const FastPasPreviewApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'FastPas POS · UI preview',
    theme: Volt.theme,
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
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
              child: Column(
                children: [
                  const Material(
                    color: Volt.lime,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Center(
                          child: Text(
                            'SAMPLE STORE · READ ONLY',
                            style: TextStyle(
                              fontSize: 11,
                              color: Volt.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, content) {
                        final media = MediaQuery.of(context);
                        return MediaQuery(
                          data: media.copyWith(
                            size: Size(width, content.maxHeight),
                            padding: media.padding.copyWith(top: 0),
                            viewPadding: media.viewPadding.copyWith(top: 0),
                          ),
                          child: child!,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    home: ProductHomeScreen(
      fullName: 'Alex Santos',
      role: 'owner',
      userId: 'preview',
      location: 'Main Branch',
      source: SampleCatalog(),
    ),
  );
}
