enum AssistantProvider {
  openai('OpenAI', 'gpt-5.6-terra', 'openaiModel'),
  gemini('Gemini', 'gemini-3.6-flash', 'geminiModel');

  final String label;
  final String defaultModel;
  final String modelPreference;
  const AssistantProvider(this.label, this.defaultModel, this.modelPreference);
  static AssistantProvider parse(String? value) =>
      values.where((provider) => provider.name == value).firstOrNull ?? openai;
}
