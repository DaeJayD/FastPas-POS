import 'package:supabase_flutter/supabase_flutter.dart';

/// Management views use the live connection unless the separate preview entry
/// point explicitly supplies an isolated, read-only client.
abstract final class StoreConnection {
  static SupabaseClient? previewClient;
  static bool get isPreview => previewClient != null;
  static SupabaseClient get client => previewClient ?? Supabase.instance.client;
}
