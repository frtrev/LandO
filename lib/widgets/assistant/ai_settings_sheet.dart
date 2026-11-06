import 'package:flutter/material.dart';
import '../../services/assistant/api_key_store.dart';
import '../../services/assistant/assistant_provider.dart';
import '../../services/assistant/local_model_store.dart';
import '../../services/property_repository.dart';

class AiSettingsSheet extends StatefulWidget {
  final ApiKeyStore keyStore;
  final PropertyRepository repository;
  final LocalModelStore? localModels;
  const AiSettingsSheet({
    super.key,
    required this.keyStore,
    required this.repository,
    this.localModels,
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
  bool queryInternet = true;
  LocalModelStore get models => widget.localModels ?? LocalModelStore.shared;
  bool get working => busy || models.downloading;
  bool get local => provider == AssistantProvider.qwen;
  void modelChanged() {
    if (!mounted) return;
    setState(() {});
    if (local && !models.downloading) refreshModelReady();
  }

  Future<void> refreshModelReady() async {
    try {
      final ready = await models.isInstalled();
      if (mounted && local) setState(() => configured = ready);
    } on Object {
      if (mounted && local) setState(() => configured = false);
    }
  }

  Future<void> downloadModel() async {
    final ready = await models.download();
    if (mounted) {
      setState(() {
        configured = ready;
        error = null;
      });
    }
  }

  Future<void> removeModel() async {
    setState(() => busy = true);
    try {
      await models.remove();
      if (mounted) setState(() => configured = false);
    } on Object {
      if (mounted) {
        setState(() => error = 'Could not remove the download. Try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    models.addListener(modelChanged);
    load();
  }

  Future<void> load() async {
    try {
      queryInternet =
          await widget.repository.preference('queryInternet') != 'false';
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
      final saved = selected == AssistantProvider.qwen
          ? await models.isInstalled()
          : (await widget.keyStore.read(provider: selected))?.isNotEmpty ??
                false;
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
      if (local) {
        if (!await models.isInstalled()) {
          throw const FormatException(
            'Download the model before selecting it.',
          );
        }
        await widget.repository.setPreference(
          'queryInternet',
          queryInternet.toString(),
        );
        await widget.repository.setPreference('aiProvider', provider.name);
      } else if (remove) {
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
        await widget.repository.setPreference(
          'queryInternet',
          queryInternet.toString(),
        );
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
    models.removeListener(modelChanged);
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
              'Choose a cloud provider with your own API key, or download an assistant that runs on this phone. Mapping works without either.',
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
                        enabled:
                            p != AssistantProvider.qwen || models.supported,
                        child: Text(
                          p == AssistantProvider.gemini
                              ? 'Gemini (Google)'
                              : p == AssistantProvider.qwen
                              ? 'Qwen (on device)'
                              : p.label,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: working
                    ? null
                    : (value) {
                        if (value != null) {
                          switchProvider(value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              if (local) ...[
                const Text(LocalModelStore.modelName),
                if (!models.supported)
                  const Text(
                    'On-device AI requires a 64-bit Android installation. Please choose a cloud provider on this phone.',
                  ),
                const SizedBox(height: 8),
                Text(
                  configured
                      ? 'Downloaded and verified. Ready for offline chat. No API key required.'
                      : 'Download once: 508 MiB. Allow at least 1 GB of free storage and use Wi-Fi. Keep the app open until the download finishes. Replies use device memory and battery; older phones may be slow or unable to run it.',
                ),
                const SizedBox(height: 8),
                if (models.downloading) ...[
                  LinearProgressIndicator(
                    value: models.verifying ? null : models.progress,
                  ),
                  Text(
                    models.verifying
                        ? 'Verifying download…'
                        : 'Downloading ${(models.received / 1048576).toStringAsFixed(0)} / 508 MiB (${(models.progress * 100).toStringAsFixed(0)}%)',
                  ),
                  TextButton(
                    onPressed: models.cancel,
                    child: const Text('Cancel download'),
                  ),
                ] else if (!configured)
                  OutlinedButton.icon(
                    onPressed: busy || !models.supported ? null : downloadModel,
                    icon: const Icon(Icons.download),
                    label: const Text('Download Qwen 3.5'),
                  )
                else
                  TextButton(
                    onPressed: busy ? null : removeModel,
                    child: const Text('Remove downloaded model'),
                  ),
                if (models.error != null)
                  Text(
                    models.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Text(
                  'Qwen team / Unsloth GGUF · Apache 2.0. Text only. Smaller local models make more mistakes than cloud models. Property backups include chats and settings; model weights must be downloaded again on a new installation.',
                ),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'LandO',
                  ),
                  child: const Text('Model and software licenses'),
                ),
              ] else ...[
                Text(
                  configured
                      ? 'A ${provider.label} key is saved securely. Leave the field empty to keep it.'
                      : 'No ${provider.label} key configured. Add a key to enable chat.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyInput,
                  enabled: !working,
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
                  enabled: !working,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '${provider.label} model ID',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Query the internet'),
                subtitle: Text(
                  local
                      ? 'Use public DuckDuckGo search snippets when needed. No search key is required. Search queries leave this phone and may include location or conversation context. Availability varies; prices are estimates, not quotes.'
                      : 'Let LandO search for current prices and other information when useful. Search queries may include property context and location. Search usage may incur additional service charges. Online information can be incomplete or inaccurate.',
                ),
                value: queryInternet,
                onChanged: working
                    ? null
                    : (value) => setState(() => queryInternet = value),
              ),
              if (provider == AssistantProvider.gemini)
                const Text(
                  'Use a Gemini Developer API key from Google AI Studio, linked to your Cloud project with Generative Language API access. Google Maps keys and Vertex AI service-account credentials are separate. Internet search alongside local calculations requires a model supporting combined search and function tools, such as Gemini 3.',
                ),
              const SizedBox(height: 8),
              Text(
                local
                    ? 'Chat and property calculations run on this phone. Only internet search queries leave the device when enabled. There are no AI API charges for local replies.'
                    : 'Sending a question shares your messages, recent conversation and app-calculated property data with ${provider.label}. Boundary details can include exact coordinates. Usage and data handling follow that provider’s account terms.',
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
                    onPressed: working || (local && !configured)
                        ? null
                        : () => save(),
                    child: Text(busy ? 'Saving…' : 'Save AI settings'),
                  ),
                  if (configured && !local)
                    TextButton(
                      onPressed: working ? null : () => save(remove: true),
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
