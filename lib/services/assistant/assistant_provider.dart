enum AssistantProvider {
  openai('OpenAI', 'gpt-5.6-terra', 'openaiModel'),
  gemini('Gemini', 'gemini-3.6-flash', 'geminiModel'),
  qwen('Qwen', 'Qwen3.5-0.8B-Q4_K_M', 'qwenModel');

  final String label;
  final String defaultModel;
  final String modelPreference;
  const AssistantProvider(this.label, this.defaultModel, this.modelPreference);
  static AssistantProvider parse(String? value) =>
      values.where((provider) => provider.name == value).firstOrNull ?? openai;
}
