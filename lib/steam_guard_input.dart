import 'package:flutter/material.dart';

class SteamGuardInput extends StatefulWidget {
  const SteamGuardInput({
    super.key,
    required this.enabled,
    required this.stopEnabled,
    required this.onSend,
    required this.onStop,
  });

  final bool enabled;
  final bool stopEnabled;
  final Future<void> Function(String code) onSend;
  final VoidCallback onStop;

  @override
  State<SteamGuardInput> createState() => _SteamGuardInputState();
}

class _SteamGuardInputState extends State<SteamGuardInput> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (!widget.enabled || _sending || code.isEmpty || code.contains('\n')) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(code);
      _controller.clear();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = '发送失败：$error';
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('steamcmd-input'),
              controller: _controller,
              enabled: widget.enabled && !_sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'SteamCMD 输入',
                hintText: '输入一行内容并发送到 SteamCMD',
                isDense: true,
              ).copyWith(errorText: _errorMessage),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('send-steamcmd-input'),
            tooltip: '发送输入',
            onPressed: widget.enabled && !_sending ? _submit : null,
            icon: const Icon(Icons.send),
          ),
          IconButton(
            key: const Key('stop-steamcmd'),
            tooltip: '停止 SteamCMD',
            onPressed: widget.stopEnabled ? widget.onStop : null,
            icon: const Icon(Icons.stop),
          ),
        ],
      ),
    );
  }
}

class SteamGuardCodeDialog extends StatefulWidget {
  const SteamGuardCodeDialog({super.key, required this.onSubmit});

  final Future<void> Function(String code) onSubmit;

  @override
  State<SteamGuardCodeDialog> createState() => _SteamGuardCodeDialogState();
}

class _SteamGuardCodeDialogState extends State<SteamGuardCodeDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _errorMessage;

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (_sending || code.isEmpty || code.contains('\n')) return;

    setState(() {
      _sending = true;
      _errorMessage = null;
    });
    try {
      await widget.onSubmit(code);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Steam Guard 验证码'),
      content: TextField(
        key: const Key('steam-guard-dialog-input'),
        controller: _controller,
        autofocus: true,
        enabled: !_sending,
        maxLines: 1,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: '验证码',
          hintText: '输入 Steam Guard 验证码',
          errorText: _errorMessage,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          key: const Key('send-steam-guard-dialog-code'),
          onPressed: _sending ? null : _submit,
          icon: const Icon(Icons.send),
          label: const Text('发送'),
        ),
      ],
    );
  }
}
