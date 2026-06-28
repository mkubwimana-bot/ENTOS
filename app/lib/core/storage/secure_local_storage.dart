import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase auth session in encrypted device storage.
///
/// Backs supabase_flutter's session persistence with flutter_secure_storage
/// (Android Keystore-backed) instead of plain SharedPreferences, so the
/// session — including the refresh token — is encrypted at rest. This is
/// required by the project's data-protection rules.
///
/// Note: supabase_flutter stores the whole session JSON under a single key.
/// Its `accessToken()`/`persistSession()` names are historical — they read and
/// write that single session string.
class SecureLocalStorage extends LocalStorage {
  const SecureLocalStorage({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  static const String _sessionKey = 'sme_os.supabase.session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => storage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => storage.read(key: _sessionKey);

  @override
  Future<void> removePersistedSession() => storage.delete(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      storage.write(key: _sessionKey, value: persistSessionString);
}
