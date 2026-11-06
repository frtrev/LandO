/// Public distribution metadata. No API keys or signing secrets belong here.
abstract final class ReleaseConfig {
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'ftrevino@yahoo.com',
  );
  static const reportEndpoint = String.fromEnvironment(
    'AI_REPORT_ENDPOINT',
    defaultValue: 'https://formsubmit.co/ajax/ftrevino@yahoo.com',
  );
  static const privacyPolicyUrl = String.fromEnvironment(
    'PRIVACY_POLICY_URL',
    defaultValue: 'https://frtrev.github.io/apps/lando/privacy/',
  );
}
