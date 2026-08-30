// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// 设置页（SettingsPage）
//
// 真正可用的设置项，所有改动即时落 BackendConfig（Hive 持久化）并同步后端：
//   1. 后端地址 —— 可改 + 一键测试连通（/health）
//   2. 情感角色 —— gentle / playful / wise（POST /persona）
//   3. 唤醒词 —— 自定义（POST /wake-word）
//   4. 数据 —— 清除对话记忆（POST /memory/clear）
//
// 上游：ProfilePage 的「设置」菜单项（context.push('/settings')）。
// 下游：BackendConfig（本地持久化）、BackendService（网络同步）。
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config.dart';
import '../../core/services/backend_service.dart';
import '../../core/theme/app_theme.dart';

/// 设置页：把资料页里原先 TODO 的「设置」项做成可用功能。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _backendUrlController = TextEditingController();
  final _wakeWordController = TextEditingController();

  String _persona = BackendConfig.instance.persona;
  bool _checking = false;
  String? _healthStatus; // 'ok' | 'fail' | null
  bool _saving = false;

  static const List<String> _personas = ['gentle', 'playful', 'wise'];
  static const Map<String, String> _personaLabels = {
    'gentle': '温柔',
    'playful': '俏皮',
    'wise': '智慧',
  };

  @override
  void initState() {
    super.initState();
    _backendUrlController.text = BackendConfig.instance.baseUrl;
    _wakeWordController.text = BackendConfig.instance.wakeWord;
  }

  @override
  void dispose() {
    _backendUrlController.dispose();
    _wakeWordController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _checking = true);
    final ok = await BackendService.instance.healthCheck();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _healthStatus = ok ? 'ok' : 'fail';
    });
  }

  Future<void> _applyBackendUrl() async {
    final url = _backendUrlController.text.trim();
    try {
      BackendConfig.instance.setBaseUrl(url);
      BackendService.instance.setBackendUrl(url);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('后端地址已更新')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('地址无效：${e.message}')),
      );
    }
  }

  Future<void> _applyPersona(String p) async {
    setState(() => _persona = p);
    BackendConfig.instance.setPersona(p); // 本地先存，离线也不丢
    try {
      await BackendService.instance.setPersona(p); // 同步后端
    } catch (_) {
      // 后端未连通时忽略网络错误，本地已保存
    }
  }

  Future<void> _applyWakeWord() async {
    final w = _wakeWordController.text.trim();
    if (w.isEmpty) return;
    BackendConfig.instance.setWakeWord(w);
    try {
      await BackendService.instance.syncWakeWord(w);
    } catch (_) {
      // 后端未连通时忽略网络错误，本地已保存
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('唤醒词已保存')),
    );
  }

  Future<void> _clearMemory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除对话记忆'),
        content: const Text('将删除竹笌记住的对话记忆，此操作不可恢复。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _saving = true);
    try {
      await BackendService.instance.clearMemory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('记忆已清除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清除失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: AppTheme.bg,
        foregroundColor: AppTheme.fg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('服务'),
          Card(
            elevation: 0,
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('后端地址', style: TextStyle(color: AppTheme.fg2, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _backendUrlController,
                    decoration: InputDecoration(
                      hintText: 'http://10.0.2.2:8000',
                      filled: true,
                      fillColor: AppTheme.surfaceSunken,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _checking ? null : _testConnection,
                        icon: _checking
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.wifi_find, size: 16),
                        label: const Text('测试连接'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _applyBackendUrl,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentDeep,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('保存地址'),
                      ),
                      if (_healthStatus == 'ok')
                        const Icon(Icons.check_circle, color: AppTheme.success, size: 20)
                      else if (_healthStatus == 'fail')
                        const Icon(Icons.error, color: AppTheme.danger, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('情感角色'),
          Card(
            elevation: 0,
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                children: _personas.map((p) {
                  final selected = _persona == p;
                  return ChoiceChip(
                    label: Text(_personaLabels[p] ?? p),
                    selected: selected,
                    onSelected: (_) => _applyPersona(p),
                    selectedColor: AppTheme.accentSoft,
                    backgroundColor: AppTheme.surfaceSunken,
                    labelStyle: TextStyle(
                      color: selected ? AppTheme.accentDeep : AppTheme.fg2,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('唤醒词'),
          Card(
            elevation: 0,
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderSoft),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _wakeWordController,
                      decoration: InputDecoration(
                        hintText: '竹笌竹笌',
                        filled: true,
                        fillColor: AppTheme.surfaceSunken,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _applyWakeWord,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentDeep,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('数据'),
          Card(
            elevation: 0,
            color: AppTheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.borderSoft),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.danger),
              title: const Text('清除对话记忆'),
              subtitle: const Text('删除竹笌记住的对话内容（不可恢复）'),
              trailing: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _saving ? null : _clearMemory,
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              '竹笌 · 让陪伴更有温度',
              style: TextStyle(color: AppTheme.meta, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置分组小标题
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.fg2,
          ),
        ),
      );
}
