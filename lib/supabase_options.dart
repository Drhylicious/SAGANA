import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseOptions {
  SupabaseOptions._();

  static const String projectUrl = 'https://nitqahryddbojbmprpmo.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5pdHFhaHJ5ZGRib2pibXBycG1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MDQ4ODMsImV4cCI6MjA5Mzk4MDg4M30.hi1-5w4v6JY4D-4_XjO4WGcrJo8EhqewkydigiQhuHM';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: projectUrl,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
}
