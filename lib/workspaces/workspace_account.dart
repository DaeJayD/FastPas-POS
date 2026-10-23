import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Account recovery state outlives individual screens and initial app links.
class WorkspaceAccount extends ChangeNotifier {
  WorkspaceAccount(this.client) {
    _auth = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) {
          recoveringPassword = true;
          _recoveryUserId = state.session?.user.id;
          notice = 'Choose a new password to finish recovering your account.';
        } else if (state.event == AuthChangeEvent.signedOut ||
            (_recoveryUserId != null &&
                state.session?.user.id != _recoveryUserId)) {
          recoveringPassword = false;
          _recoveryUserId = null;
        }
        _notify();
      },
      onError: (_) {
        notice = 'Could not refresh your account. Check your connection.';
        _notify();
      },
    );
  }

  static const callbackUrl = 'fastpas://auth-callback';
  final SupabaseClient client;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<Uri>? _links;
  final _handledLinks = <String>{};
  Future<void> _linkQueue = Future.value();
  bool _disposed = false;
  bool recoveringPassword = false;
  String? notice;
  String? _recoveryUserId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static String checkedEmail(String input) {
    final email = input.trim();
    if (email.length > 320 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const FormatException('Enter a valid email address.');
    }
    return email;
  }

  static void checkedPassword(String password) {
    if (password.length < 8) {
      throw const FormatException(
        'Use at least 8 characters for your password.',
      );
    }
  }

  Future<void> signIn(String email, String password) async {
    final address = checkedEmail(email);
    if (password.isEmpty) throw const FormatException('Enter your password.');
    await client.auth
        .signInWithPassword(email: address, password: password)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> signUp(String email, String password) async {
    final address = checkedEmail(email);
    checkedPassword(password);
    await client.auth
        .signUp(
          email: address,
          password: password,
          emailRedirectTo: callbackUrl,
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> sendPasswordReset(String email) async {
    await client.auth
        .resetPasswordForEmail(checkedEmail(email), redirectTo: callbackUrl)
        .timeout(const Duration(seconds: 15));
  }

  Future<void> resendVerification(String email) async {
    await client.auth
        .resend(
          type: OtpType.signup,
          email: checkedEmail(email),
          emailRedirectTo: callbackUrl,
        )
        .timeout(const Duration(seconds: 15));
  }

  Future<void> finishRecovery(String password, String confirmation) async {
    final actor = _recoveryUserId;
    if (!recoveringPassword ||
        actor == null ||
        client.auth.currentUser?.id != actor) {
      throw StateError('Open the password reset link first.');
    }
    checkedPassword(password);
    if (password != confirmation) {
      throw const FormatException('The passwords do not match.');
    }
    await client.auth
        .updateUser(UserAttributes(password: password))
        .timeout(const Duration(seconds: 15));
    if (client.auth.currentUser?.id != actor) {
      throw StateError('Your recovery session ended. Open a new reset link.');
    }
    recoveringPassword = false;
    _recoveryUserId = null;
    notice = 'Password updated. Your business records have not changed.';
    _notify();
  }

  Future<void> cancelRecovery() async {
    // Clear local credentials even when server logout cannot be reached.
    try {
      await client.auth
          .signOut(scope: SignOutScope.local)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      if (client.auth.currentSession != null) rethrow;
    } finally {
      recoveringPassword = false;
      _recoveryUserId = null;
      notice = 'Sign in when you are ready.';
      _notify();
    }
  }

  static bool acceptsCallback(Uri uri) =>
      uri.scheme == 'fastpas' &&
      uri.host == 'auth-callback' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      (uri.path.isEmpty || uri.path == '/');

  /// The SDK exchanges the code using the verifier saved on this device.
  /// This handler never logs or persists callback URLs. The SDK owns session storage.
  Future<bool> openAuthLink(Uri uri) {
    final result = Completer<bool>();
    _linkQueue = _linkQueue.then((_) async {
      if (_disposed ||
          !acceptsCallback(uri) ||
          _handledLinks.contains(uri.toString())) {
        result.complete(false);
        return;
      }
      try {
        if ((uri.queryParameters['code'] ?? '').isEmpty) {
          throw const FormatException('Missing callback code');
        }
        await client.auth
            .getSessionFromUrl(uri)
            .timeout(const Duration(seconds: 15));
        _handledLinks.add(uri.toString());
        if (_handledLinks.length > 32) {
          _handledLinks.remove(_handledLinks.first);
        }
        if (!recoveringPassword) {
          notice = 'Email verified. You can continue with your businesses.';
        }
        _notify();
        result.complete(true);
      } catch (_) {
        notice = 'This account link could not be opened. Request a fresh email and open it on the device that requested it.';
        _notify();
        result.complete(false);
      }
    });
    return result.future;
  }

  void attachLinks(Stream<Uri> links, Future<Uri?> initialLink) {
    _links?.cancel();
    _links = links.listen(
      (uri) {
        unawaited(openAuthLink(uri));
      },
      onError: (_) {
        notice =
            'Could not open the account link. Try opening the email again.';
        _notify();
      },
    );
    unawaited(
      initialLink
          .then((uri) async {
            if (uri != null && !_disposed) await openAuthLink(uri);
          })
          .catchError((Object _) {
            notice =
                'Could not read the account link. Try opening the email again.';
            _notify();
          }),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.cancel();
    _links?.cancel();
    super.dispose();
  }
}
