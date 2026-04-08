import 'package:flutter/material.dart';

import '../notes/sync_models.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    required this.apiBaseUrlController,
    required this.emailController,
    required this.passwordController,
    required this.session,
    required this.syncMessage,
    required this.isAuthenticating,
    required this.onBootstrap,
    required this.onLogin,
    super.key,
  });

  final TextEditingController apiBaseUrlController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final SyncSession? session;
  final String? syncMessage;
  final bool isAuthenticating;
  final Future<void> Function() onBootstrap;
  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF1C6E5B),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session == null ? 'Account setup' : 'Sync account',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            if (session != null)
              Text(
                'Signed in as ${session!.email}',
                style: const TextStyle(color: Colors.white),
              ),
            if (session == null) ...[
              _SyncField(
                controller: apiBaseUrlController,
                label: 'Sync API URL',
              ),
              const SizedBox(height: 8),
              _SyncField(
                controller: emailController,
                label: 'Email',
              ),
              const SizedBox(height: 8),
              _SyncField(
                controller: passwordController,
                label: 'Password',
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: isAuthenticating ? null : onBootstrap,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1C6E5B),
                      ),
                      child: Text(
                          isAuthenticating ? 'Working...' : 'Create account'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isAuthenticating ? null : onLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white70),
                      ),
                      child: const Text('Sign in'),
                    ),
                  ),
                ],
              ),
            ],
            if (syncMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                syncMessage!,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SyncField extends StatelessWidget {
  const _SyncField({
    required this.controller,
    required this.label,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white54),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white),
        ),
      ),
    );
  }
}
