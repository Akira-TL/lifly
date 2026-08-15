import 'package:client_flutter/data/ai/ai_provider.dart';
import 'package:flutter/material.dart';

class CloudAiConsentDecision {
  const CloudAiConsentDecision({required this.provider, required this.model});

  final AiProviderKind provider;
  final String model;
}

Future<CloudAiConsentDecision?> showCloudAiConsentDialog(
  BuildContext context, {
  required String inputText,
  required int selectedAssetCount,
  AiProviderKind initialProvider = AiProviderKind.ollama,
  String initialModel = '',
}) {
  return showDialog<CloudAiConsentDecision>(
    context: context,
    builder: (context) => _CloudAiConsentDialog(
      inputText: inputText,
      selectedAssetCount: selectedAssetCount,
      initialProvider: initialProvider,
      initialModel: initialModel,
    ),
  );
}

class _CloudAiConsentDialog extends StatefulWidget {
  const _CloudAiConsentDialog({
    required this.inputText,
    required this.selectedAssetCount,
    required this.initialProvider,
    required this.initialModel,
  });

  final String inputText;
  final int selectedAssetCount;
  final AiProviderKind initialProvider;
  final String initialModel;

  @override
  State<_CloudAiConsentDialog> createState() => _CloudAiConsentDialogState();
}

class _CloudAiConsentDialogState extends State<_CloudAiConsentDialog> {
  late AiProviderKind _provider = widget.initialProvider;
  late final TextEditingController _modelController = TextEditingController(
    text: widget.initialModel,
  );
  bool _confirmed = false;

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.inputText.length > 180
        ? '${widget.inputText.substring(0, 180)}…'
        : widget.inputText;
    final model = _modelController.text.trim();
    return AlertDialog(
      title: const Text('本次授权 Cloud AI'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('只授权一次。本次仅披露下面的当前输入，不发送历史会话。'),
            const SizedBox(height: 12),
            DropdownButtonFormField<AiProviderKind>(
              key: const Key('cloud_ai_provider'),
              initialValue: _provider,
              decoration: const InputDecoration(
                labelText: 'Cloud Provider',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: AiProviderKind.ollama,
                  child: Text('Ollama'),
                ),
                DropdownMenuItem(
                  value: AiProviderKind.openAiCompatible,
                  child: Text('OpenAI-compatible'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _provider = value);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('cloud_ai_model'),
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: 'Model（必须与服务端配置一致）',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            const Text('披露内容：'),
            const SizedBox(height: 4),
            SelectableText(preview),
            const SizedBox(height: 8),
            Text('附件：${widget.selectedAssetCount} 个，不发送'),
            const Text('历史会话：不发送'),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const Key('cloud_ai_once_consent'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              title: const Text('我确认本次将上述当前输入发送给 Cloud AI'),
              onChanged: (value) => setState(() => _confirmed = value ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('cloud_ai_consent_confirm'),
          onPressed: _confirmed && model.isNotEmpty
              ? () => Navigator.of(
                  context,
                ).pop(CloudAiConsentDecision(provider: _provider, model: model))
              : null,
          child: const Text('仅本次允许并发送'),
        ),
      ],
    );
  }
}
