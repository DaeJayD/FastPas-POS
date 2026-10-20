import 'package:flutter/material.dart';

import '../auth/login_screen.dart';
import '../pos/product_home_screen.dart';
import '../preview/sample_catalog.dart';
import 'pos_session.dart';
import 'store_connection.dart';

abstract final class StoreNavigation {
  static void home(BuildContext context, PosSession session) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ProductHomeScreen(
          fullName: session.fullName,
          role: session.role,
          userId: session.userId,
          location: session.location,
          source: session.preview ? SampleCatalog() : null,
        ),
      ),
      (_) => false,
    );
  }

  static Future<void> signOut(BuildContext context) async {
    if (!StoreConnection.isPreview) await StoreConnection.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }
}
