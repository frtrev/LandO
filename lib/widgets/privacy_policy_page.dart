import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/release_config.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  Future<void> open(BuildContext context, Uri url) async {
    try {
      if (await launchUrl(
        url,
        mode: url.scheme == 'https'
            ? LaunchMode.externalApplication
            : LaunchMode.platformDefault,
      )) {
        return;
      }
    } on Object {
      /* Keep the policy readable if no handler is installed. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open this link. Contact ftrevino@yahoo.com for support.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & support')),
    body: FutureBuilder<String>(
      future: rootBundle.loadString('assets/legal/privacy-policy.txt'),
      builder: (context, snapshot) => snapshot.hasData
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(snapshot.data!),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: () => open(
                      context,
                      Uri(
                        scheme: 'mailto',
                        path: ReleaseConfig.supportEmail,
                        queryParameters: {'subject': 'LandO support'},
                      ),
                    ),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Contact support'),
                  ),
                  if (Uri.tryParse(ReleaseConfig.privacyPolicyUrl)?.scheme ==
                      'https')
                    TextButton(
                      onPressed: () => open(
                        context,
                        Uri.parse(ReleaseConfig.privacyPolicyUrl),
                      ),
                      child: const Text('Public privacy policy'),
                    ),
                  TextButton(
                    onPressed: () => showLicensePage(
                      context: context,
                      applicationName: 'LandO',
                    ),
                    child: const Text('Open-source licenses'),
                  ),
                ],
              ),
            )
          : snapshot.hasError
          ? const Center(
              child: Text(
                'Could not load the policy. Contact ftrevino@yahoo.com.',
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    ),
  );
}
