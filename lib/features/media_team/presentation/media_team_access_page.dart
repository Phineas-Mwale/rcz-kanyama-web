import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_team_dashboard_page.dart';

class MediaTeamAccessPage extends StatefulWidget {
  const MediaTeamAccessPage({super.key});

  @override
  State<MediaTeamAccessPage> createState() => _MediaTeamAccessPageState();
}

class _MediaTeamAccessPageState extends State<MediaTeamAccessPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;
  bool _checkingSession = true;
  String? _statusMessage;
  bool _statusIsError = false;

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    _message(message);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_checkExistingSession());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null &&
          !user.isAnonymous &&
          (user.userMetadata?['requested_role']?.toString().toUpperCase() ==
              'MEDIA')) {
        await _checkAccess(user.id);
        return;
      }
    } catch (error) {
      // A stored session can fail to load on a flaky connection. The sign-in
      // form is still usable, so do not block the page.
      debugPrint('Media Team session check failed: $error');
    } finally {
      if (mounted) setState(() => _checkingSession = false);
    }
  }

  String _normaliseContactPhone(String value) {
    var phone = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (phone.startsWith('0')) {
      phone = '+260${phone.substring(1)}';
    } else if (phone.startsWith('260')) {
      phone = '+$phone';
    }
    return phone;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final phone = _normaliseContactPhone(_phone.text);
    final password = _password.text;

    if (_creating && name.isEmpty) {
      _message('Enter your full name.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _message('Enter a valid email address.');
      return;
    }
    if (_creating && !RegExp(r'^\+260\d{9}$').hasMatch(phone)) {
      _message('Enter a valid Zambian phone number, for example 0971234567.');
      return;
    }
    if (password.length < 8) {
      _message('Your password must be at least 8 characters long.');
      return;
    }
    if (_creating && password != _confirmPassword.text) {
      _message('The two passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_creating) {
        final response = await auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'contact_phone': phone,
            'requested_role': 'MEDIA',
          },
        );
        if (response.user == null) {
          _message('Account creation did not complete. Please try again.');
        } else if (response.session == null) {
          setState(() => _creating = false);
          _setStatus(
            'Account created. Check your email for the confirmation link, then sign in. A church administrator must approve Media Team access.',
          );
        } else if (response.user?.emailConfirmedAt == null) {
          setState(() => _creating = false);
          _setStatus(
            'Account created. Please confirm your email address before signing in. Your application is awaiting administrator approval.',
          );
        } else {
          await _checkAccess(response.user!.id);
        }
      } else {
        final response = await auth.signInWithPassword(
          email: email,
          password: password,
        );
        final user = response.user;
        if (user == null) {
          _message('Login was unsuccessful.');
        } else if (user.emailConfirmedAt == null) {
          _message('Please confirm your email address before signing in.');
        } else {
          await _checkAccess(user.id);
        }
      }
    } on AuthException catch (error) {
      _message(error.message);
    } on PostgrestException catch (error) {
      _setStatus(
        'Account authenticated, but Media Team access could not be checked: ${error.message}',
        isError: true,
      );
    } catch (error) {
      _setStatus(
        'Could not complete the request. Check your connection and try again.',
        isError: true,
      );
      debugPrint('Media Team access error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _safeSignOut() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Media Team sign-out failed: $error');
    }
  }

  Future<void> _checkAccess(String userId) async {
    final client = Supabase.instance.client;
    try {
      final row = await client
          .from('media_team_accounts')
          .select('display_name,is_active,status')
          .eq('user_id', userId)
          .maybeSingle();
      if (!mounted) return;
      if (row == null) {
        await _safeSignOut();
        if (!mounted) return;
        _setStatus(
          'This account is not registered for Media Team access. Create a Media Team account or ask the administrator to check your record.',
          isError: true,
        );
        return;
      }
      final status = row['status']?.toString();
      if (status == 'rejected') {
        await _safeSignOut();
        if (!mounted) return;
        _setStatus(
          'Your application was not approved. Please contact the church administrator.',
          isError: true,
        );
        return;
      }
      if (row['is_active'] != true) {
        await _safeSignOut();
        if (!mounted) return;
        if (status == 'inactive') {
          _setStatus(
            'Your account is currently inactive. Please contact the church administrator.',
            isError: true,
          );
        } else {
          _setStatus(
            'Your Media Team account is waiting for approval. A church administrator must activate it before you can sign in.',
          );
        }
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => MediaTeamDashboardPage(
            displayName:
                row['display_name']?.toString().trim().isNotEmpty ?? false
                ? row['display_name'].toString().trim()
                : _name.text.trim().isNotEmpty
                ? _name.text.trim()
                : 'Media Team',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      await _safeSignOut();
      if (!mounted) return;
      if (error.code == 'PGRST205' ||
          error.message.contains('schema cache') ||
          error.message.contains('Could not find the table')) {
        _setStatus(
          'Media Team access has not been configured in Supabase yet. Ask the church administrator to run the corrective migration.',
          isError: true,
        );
      } else if (error.code == '42501') {
        _setStatus(
          'This account is not allowed to read Media Team records.',
          isError: true,
        );
      } else {
        _setStatus(
          'Media Team access could not be checked: ${error.message}',
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      _setStatus(
        'Media Team access could not be checked. Check your connection and try again.',
        isError: true,
      );
      debugPrint('Media Team authorisation failed: $error');
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Media Team access')),
      body: _checkingSession
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                  children: [
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: colors.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colors.secondary.withValues(alpha: .16),
                          ),
                        ),
                        child: Icon(
                          Icons.perm_media_outlined,
                          size: 29,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _creating ? 'Join the Media Team' : 'Kanyama Media Team',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This area is for the congregation Media Team. Register '
                      'with your email address and phone number. Access is '
                      'granted after a church administrator approves your '
                      'account.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_statusMessage != null) ...[
                      _StatusBanner(
                        message: _statusMessage!,
                        isError: _statusIsError,
                        onDismiss: () => setState(() => _statusMessage = null),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_creating) ...[
                              TextField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Full name',
                                  prefixIcon: Icon(Icons.person_outline),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Phone number',
                                  hintText: '0971234567',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textCapitalization: TextCapitalization.none,
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _password,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            if (_creating) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: _confirmPassword,
                                obscureText: _obscure,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _creating
                                          ? 'Create Media Team account'
                                          : 'Sign in',
                                    ),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _creating = !_creating;
                                      _statusMessage = null;
                                    }),
                              child: Text(
                                _creating ? 'Already registered? Sign in' : 'New to the Media Team? Create an account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Only active Media Team accounts can manage the congregation archive.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Persistent, dismissible feedback for pending or failed authorisation.
///
/// A snack bar alone is too easy to miss (and disappears before a person can
/// read a long approval message), so the same message stays inline.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = isError
        ? colors.errorContainer
        : colors.secondaryContainer;
    final foreground = isError
        ? colors.onErrorContainer
        : colors.onSecondaryContainer;
    final border = isError ? colors.error : colors.secondary;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border.withValues(alpha: .28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError
                  ? Icons.error_outline_rounded
                  : Icons.hourglass_empty_rounded,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss message',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded, size: 18, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}
