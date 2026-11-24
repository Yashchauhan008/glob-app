import 'package:flutter/material.dart';
import '../api.dart';
import 'workspaces_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _otp = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _regToken;
  String _err = '';

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      _busy = true;
      _err = '';
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done(dynamic r) async {
    await Api.signIn('${r['token']}', Map<String, dynamic>.from(r['user'] as Map));
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WorkspacesPage()), (_) => false);
  }

  Future<void> _submit() => _run(() async {
        final email = _email.text.trim().toLowerCase();
        if (_regToken != null) {
          final r = await Api.post('/auth/verify-registration',
              {'token': _regToken, 'otp': _otp.text.trim()});
          _done(r);
        } else if (_register) {
          final r = await Api.post('/auth/register',
              {'name': _name.text.trim(), 'email': email, 'password': _pass.text});
          setState(() => _regToken = '${r['token']}');
        } else {
          final r = await Api.post('/auth/login', {'email': email, 'password': _pass.text});
          _done(r);
        }
      });

  @override
  Widget build(BuildContext context) {
    final verifying = _regToken != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Glob',
                      style: Theme.of(context)
                          .textTheme
                          .displaySmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                      verifying
                          ? 'Enter the 6-digit code we emailed you'
                          : _register
                              ? 'Create your account'
                              : 'Welcome back! Enter your details',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  if (verifying)
                    TextField(
                        controller: _otp,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                            labelText: 'Code', border: OutlineInputBorder()))
                  else ...[
                    if (_register) ...[
                      TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                              labelText: 'Name', border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _pass,
                        obscureText: _hide,
                        decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                                onPressed: () => setState(() => _hide = !_hide)))),
                  ],
                  if (_err.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_err,
                            style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 20),
                  FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(_busy
                              ? 'Please wait…'
                              : verifying
                                  ? 'Verify & continue'
                                  : _register
                                      ? 'Continue'
                                      : 'Log in'))),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                if (verifying) {
                                  _regToken = null;
                                } else {
                                  _register = !_register;
                                }
                                _err = '';
                              }),
                      child: Text(verifying
                          ? 'Start over'
                          : _register
                              ? 'Already have an account? Log in'
                              : "Don't have an account? Sign up")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
