import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemosyne/src/features/onboarding/onboarding_card.dart';
import 'package:mnemosyne/src/features/notes/sync_models.dart';

void main() {
  testWidgets('shows account creation actions when signed out', (tester) async {
    final apiController =
        TextEditingController(text: 'https://api.example.com');
    final emailController = TextEditingController(text: 'user@example.com');
    final passwordController = TextEditingController(text: 'secret');
    addTearDown(apiController.dispose);
    addTearDown(emailController.dispose);
    addTearDown(passwordController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingCard(
            apiBaseUrlController: apiController,
            emailController: emailController,
            passwordController: passwordController,
            session: null,
            syncMessage: 'Ready to sync',
            isAuthenticating: false,
            onBootstrap: () async {},
            onLogin: () async {},
            onRecover: () async {},
            onConsumeApproval: () async {},
            onStartApproval: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Account setup'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Use recovery key'), findsOneWidget);
    expect(find.text('Use approval code'), findsOneWidget);
    expect(find.text('Ready to sync'), findsOneWidget);
  });

  testWidgets('shows signed-in actions when session is present',
      (tester) async {
    final apiController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    addTearDown(apiController.dispose);
    addTearDown(emailController.dispose);
    addTearDown(passwordController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnboardingCard(
            apiBaseUrlController: apiController,
            emailController: emailController,
            passwordController: passwordController,
            session: SyncSession(
              accountId: 'acct_1',
              sessionToken: 'session_1',
              email: 'user@example.com',
              sessionExpiresAt: DateTime.parse('2026-04-10T12:00:00Z'),
              encryptedMasterKeyForPassword: 'enc-pw',
              encryptedMasterKeyForRecovery: 'enc-rec',
              wrappedMasterKeyForApproval: '',
              masterKeyMaterial: 'master-key',
              recoveryKeyHint: 'first pet',
            ),
            syncMessage: null,
            isAuthenticating: false,
            onBootstrap: () async {},
            onLogin: () async {},
            onRecover: () async {},
            onConsumeApproval: () async {},
            onStartApproval: () async {},
            onSignOut: () async {},
          ),
        ),
      ),
    );

    expect(find.text('Sync account'), findsOneWidget);
    expect(find.text('Signed in as user@example.com'), findsOneWidget);
    expect(find.text('Approve new device'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
  });
}
