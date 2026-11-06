import 'package:flutter/material.dart';
import '../../services/assistant/assistant_provider.dart';
import '../../services/property_repository.dart';
import '../privacy_policy_page.dart';

abstract final class AssistantSharingConsent {
  static String key(AssistantProvider provider, bool internet) =>
      'assistantConsent:v1:${provider.name}:${internet ? 'web' : 'offline'}';
  static Future<bool> request(
    BuildContext context,
    PropertyRepository repository,
    AssistantProvider provider,
    bool internet,
  ) async {
    final local = provider == AssistantProvider.qwen;
    if (local && !internet) return true;
    final preference = key(provider, internet);
    if (await repository.preference(preference) == 'true') return true;
    if (!context.mounted) return false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          local ? 'Allow internet research?' : 'Allow assistant data sharing?',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                local
                    ? 'Your assistant runs on this phone. Internet research sends search queries to DuckDuckGo. Queries may include location or information from your question and conversation.'
                    : 'Sending shares your question, recent conversation and property data—including possible precise coordinates—with the cloud AI provider you selected in AI settings. That provider processes the information under its account terms.',
              ),
              if (!local && internet)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Internet research is enabled. Search services may also receive queries containing location or property context.',
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'You can decline and keep using the map, change providers, or turn off Query the internet in AI settings. Avoid sharing sensitive information.',
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => const PrivacyPolicyPage(),
                  ),
                ),
                child: const Text('Read privacy policy'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Agree & send'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    await repository.setPreference(preference, 'true');
    return true;
  }
}
