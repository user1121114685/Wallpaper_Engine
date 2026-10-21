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

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (!widget.enabled || _sending || code.isEmpty || code.contains('\n')) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSend(code);
      _controller.clear();
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
              key: const Key('steam-guard-code'),
              controller: _controller,
              enabled: widget.enabled && !_sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Steam Guard 验证码',
                hintText: '验证码出现在运行日志后输入',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const Key('send-steam-guard-code'),
            tooltip: '发送验证码',
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
