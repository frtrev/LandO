import 'package:flutter/material.dart';
import '../../services/assistant/api_key_store.dart';
import '../../services/assistant/assistant_provider.dart';
import '../../services/property_repository.dart';

class AiSettingsSheet extends StatefulWidget {
  final ApiKeyStore keyStore;
  final PropertyRepository repository;
  const AiSettingsSheet({
    super.key,
    required this.keyStore,
    required this.repository,
  });
  @override
  State<AiSettingsSheet> createState() => _AiSettingsSheetState();
}

class _AiSettingsSheetState extends State<AiSettingsSheet> {
  final keyInput = TextEditingController(),
      modelInput = TextEditingController();
  final Map<AssistantProvider, String> _keyDrafts = {}, _modelDrafts = {};
  AssistantProvider provider = AssistantProvider.openai;
  bool loading = true, busy = false, configured = false, visible = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      provider = AssistantProvider.parse(
        await widget.repository.preference('aiProvider'),
      );
      await loadProvider(provider);
    } on Object {
      if (mounted) {
        setState(() {
          error = 'Could not read secure AI settings. Please try again.';
          loading = false;
        });
      }
    }
  }

  Future<void> loadProvider(AssistantProvider selected) async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        visible = false;
      });
    }
    try {
      final saved =
          (await widget.keyStore.read(provider: selected))?.isNotEmpty ?? false;
      final model =
          _modelDrafts[selected] ??
          await widget.repository.preference(selected.modelPreference) ??
          selected.defaultModel;
      if (!mounted) {
        return;
      }
      provider = selected;
      configured = saved;
      keyInput.text = _keyDrafts[selected] ?? '';
      modelInput.text = model;
    } on Object {
      if (mounted) {
        setState(
          () => error = 'Could not read secure AI settings. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> switchProvider(AssistantProvider value) async {
    _keyDrafts[provider] = keyInput.text;
    _modelDrafts[provider] = modelInput.text;
    await loadProvider(value);
  }

  Future<void> save({bool remove = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await widget.keyStore.delete(provider: provider);
      } else {
        final key = keyInput.text.trim();
        var model = modelInput.text.trim();
        if (provider == AssistantProvider.gemini) {
          model = model.replaceFirst(RegExp(r'^models/'), '');
        }
        if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$').hasMatch(model)) {
          throw const FormatException('Enter a valid model ID.');
        }
        if (key.contains(RegExp(r'\s'))) {
          throw const FormatException('API keys cannot contain whitespace.');
        }
        if (key.isNotEmpty &&
            provider == AssistantProvider.openai &&
            !key.startsWith('sk-')) {
          throw const FormatException(
            'Enter an OpenAI API key starting with sk-.',
          );
        }
        if (key.isNotEmpty &&
            provider == AssistantProvider.gemini &&
            key.startsWith('sk-')) {
          throw const FormatException(
            'This looks like an OpenAI key. Enter a Gemini API key.',
          );
        }
        if (key.isNotEmpty) {
          await widget.keyStore.save(key, provider: provider);
        }
        await widget.repository.setPreference(provider.modelPreference, model);
        // Publish the selection after its key/model have been written.
        await widget.repository.setPreference('aiProvider', provider.name);
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : 'Could not update secure AI settings. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  void dispose() {
    keyInput.dispose();
    modelInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LandO assistant settings',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose your AI provider. Each provider has its own securely saved key and model. Mapping works without either.',
            ),
            const SizedBox(height: 12),
            if (loading)
              const LinearProgressIndicator()
            else ...[
              DropdownButtonFormField<AssistantProvider>(
                key: ValueKey(provider),
                initialValue: provider,
                decoration: const InputDecoration(
                  labelText: 'AI provider',
                  border: OutlineInputBorder(),
                ),
                items: AssistantProvider.values
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          p == AssistantProvider.gemini
                              ? 'Gemini (Google)'
                              : p.label,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (value) {
                        if (value != null) {
                          switchProvider(value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              Text(
                configured
                    ? 'A ${provider.label} key is saved securely. Leave the field empty to keep it.'
                    : 'No ${provider.label} key configured. Add a key to enable chat.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyInput,
                enabled: !busy,
                obscureText: !visible,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                decoration: InputDecoration(
                  labelText: configured
                      ? 'Replace ${provider.label} API key'
                      : '${provider.label} API key',
                  hintText: provider == AssistantProvider.openai
                      ? 'sk-…'
                      : 'Gemini API key',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: visible ? 'Hide key' : 'Show key',
                    onPressed: () => setState(() => visible = !visible),
                    icon: Icon(
                      visible ? Icons.visibility_off : Icons.visibility,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelInput,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '${provider.label} model ID',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (provider == AssistantProvider.gemini)
                const Text(
                  'Use a Gemini Developer API key from Google AI Studio, linked to your Cloud project with Generative Language API access. Google Maps keys and Vertex AI service-account credentials are separate.',
                ),
              const SizedBox(height: 8),
              Text(
                'Sending a question shares your messages, recent conversation and app-calculated property data with ${provider.label}. Boundary details can include exact coordinates. Usage and data handling follow that provider’s account terms.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Save selects this provider and model. The other provider’s key is retained. LandO never falls back to another provider automatically.',
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : () => save(),
                    child: Text(busy ? 'Saving…' : 'Save AI settings'),
                  ),
                  if (configured)
                    TextButton(
                      onPressed: busy ? null : () => save(remove: true),
                      child: const Text('Remove API key'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
