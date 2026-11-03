import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'assistant_provider.dart';

abstract class ApiKeyStore {
  Future<String?> read({AssistantProvider provider = AssistantProvider.openai});
  Future<void> save(
    String key, {
    AssistantProvider provider = AssistantProvider.openai,
  });
  Future<void> delete({AssistantProvider provider = AssistantProvider.openai});
}

class SecureApiKeyStore implements ApiKeyStore {
  final FlutterSecureStorage storage;
  SecureApiKeyStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );
  static const keyName = 'lando.openai.apiKey';
  @override
  Future<String?> read({
    AssistantProvider provider = AssistantProvider.openai,
  }) => storage.read(key: 'lando.${provider.name}.apiKey');
  @override
  Future<void> save(
    String key, {
    AssistantProvider provider = AssistantProvider.openai,
  }) => storage.write(key: 'lando.${provider.name}.apiKey', value: key.trim());
  @override
  Future<void> delete({
    AssistantProvider provider = AssistantProvider.openai,
  }) => storage.delete(key: 'lando.${provider.name}.apiKey');
}

const defaultAssistantModel = 'gpt-5.6-terra';
