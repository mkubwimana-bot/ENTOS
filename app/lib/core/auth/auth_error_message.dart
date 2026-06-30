import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps Supabase [AuthException]s to clearer messages for the UI.
String authErrorMessage(AuthException error) {
  final message = error.message.toLowerCase();

  if (message.contains('email') && message.contains('invalid')) {
    return 'Supabase rejected this email address. Addresses like '
        'dev@smeos.test work for dev login (created via SQL) but cannot '
        'receive reset or signup emails. Use a real email you can open on '
        'this phone, or run tests/003_dev_email_for_password_reset.sql '
        'in Supabase to point the dev user at your inbox.';
  }

  return error.message;
}
