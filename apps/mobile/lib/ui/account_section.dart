import 'package:flutter/material.dart';

import '../account/account.dart';
import '../account/account_config.dart';
import 'kit/pixel_theme.dart';

/// Settings rows for the optional account: guest by default, with Google
/// and Facebook buttons that keep progress safe across phones.
class AccountSection extends StatelessWidget {
  const AccountSection({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AccountScope.of(context);
    if (account == null || !account.available) {
      return _note(
        'Playing as a guest. Sign-in with Google or Facebook is not set up '
        'in this build yet.',
      );
    }
    final user = account.user;
    if (user == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _note(
            'Playing as a guest. Sign in to keep your hats, awards and best '
            'times if you change phones. Your progress so far comes with you.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _SignInButton(
                key: const Key('sign-in-google'),
                label: 'Sign in with Google',
                icon: 'G',
                color: Px.paper,
                textColor: Px.ink,
                busy: account.busy,
                onTap: () => _run(context, account.signIn(SignInMethod.google)),
              ),
              if (facebookLoginEnabled)
                _SignInButton(
                  key: const Key('sign-in-facebook'),
                  label: 'Sign in with Facebook',
                  icon: 'f',
                  color: const Color(0xFF1877F2),
                  textColor: Colors.white,
                  busy: account.busy,
                  onTap: () =>
                      _run(context, account.signIn(SignInMethod.facebook)),
                ),
            ],
          ),
        ],
      );
    }
    final via = user.method == SignInMethod.google ? 'Google' : 'Facebook';
    final who = [user.name, user.email].where((s) => s.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _note(
          'Signed in with $via${who.isEmpty ? '' : ': $who'}. '
          'Progress syncs to your account.',
          color: Px.paper,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton(
              key: const Key('sign-out'),
              onPressed: account.busy
                  ? null
                  : () => _run(context, account.signOut()),
              child: Text('Sign out', style: Px.label(13, color: Px.fuse)),
            ),
            const SizedBox(width: 12),
            TextButton(
              key: const Key('delete-account'),
              onPressed: account.busy
                  ? null
                  : () => _confirmDelete(context, account),
              child: Text(
                'Delete account',
                style: Px.label(13, color: Px.danger),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _note(String text, {Color color = Px.muted}) =>
      Text(text, style: Px.label(13, color: color, bold: false));

  static Future<void> _run(BuildContext context, Future<void> work) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await work;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is AccountError ? e.message : '$e')),
      );
    }
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    Account account,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Px.panel,
        title: Text('Delete account?', style: Px.title(12)),
        content: Text(
          'This removes your account and its cloud copy. Progress on this '
          'phone stays, and you keep playing as a guest.',
          style: Px.label(13, bold: false),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Keep it', style: Px.label(13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: Px.label(13, color: Px.danger)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await _run(context, account.deleteAccount());
    }
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String icon;
  final Color color;
  final Color textColor;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: color,
      foregroundColor: textColor,
      shape: const RoundedRectangleBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    onPressed: busy ? null : onTap,
    icon: Text(icon, style: Px.title(12, color: textColor)),
    label: Text(label, style: Px.label(13, color: textColor)),
  );
}
