import 'package:flutter/material.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({super.key});

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
              'First-run checklist',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            const Text(
              '1. Create or sign in to your account\n'
              '2. Save your recovery key\n'
              '3. Choose a local Markdown folder\n'
              '4. Add another device when ready',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

