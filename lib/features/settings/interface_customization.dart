import 'package:flutter/material.dart';
import 'package:venera_next/components/settings_save_state.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/foundation/interface_customization.dart';
import 'appearance.dart';
import 'explore_settings.dart';
import 'reader.dart';

class InterfaceCustomizationSettings extends StatefulWidget {
  const InterfaceCustomizationSettings({super.key});
  @override
  State<InterfaceCustomizationSettings> createState() =>
      _InterfaceCustomizationSettingsState();
}

class _InterfaceCustomizationSettingsState
    extends SettingsSaveState<InterfaceCustomizationSettings> {
  late List<String> _home, _toolbar, _navigation;
  late Set<String> _hiddenHome, _hiddenToolbar;
  static const _labels = {
    'sync': '同步状态',
    'history': '阅读历史',
    'later': '稍后阅读',
    'local': '本地漫画',
    'updates': '追更',
    'sources': '漫画源',
    'images': '图片收藏',
    'collect': '收藏图片',
    'fullscreen': '全屏',
    'rotate': '旋转屏幕',
    'brightness': '亮度',
    'automatic': '自动阅读',
    'chapters': '章节目录',
    'mask': '图片遮罩',
    'crop': '裁切图片',
    'reload': '重新加载图片',
    'verify': '网站验证',
    'save': '保存图片',
    'share': '分享',
    'home': '主页',
    'favorites': '收藏',
    'explore': '发现',
    'categories': '分类',
  };
  @override
  void initState() {
    super.initState();
    _load(
      InterfaceCustomization.read(
        appdata.settings[InterfaceCustomization.storageKey],
      ),
    );
  }

  void _load(InterfaceCustomization value) {
    _home = [...value.homeOrder];
    _toolbar = [...value.toolbarOrder];
    _navigation = [...value.navigationOrder];
    _hiddenHome = {...value.hiddenHome};
    _hiddenToolbar = {...value.hiddenToolbar};
  }

  Future<void> _save() async {
    if (!acceptsSettingsChanges || savingSettings) return;
    // Freeze the draft before asynchronous persistence; drag gestures never save.
    final value = InterfaceCustomization.read({
      'homeOrder': [..._home],
      'toolbarOrder': [..._toolbar],
      'navigationOrder': [..._navigation],
      'hiddenHome': [..._hiddenHome],
      'hiddenToolbar': [..._hiddenToolbar],
    }).toJson();
    await saveSetting(
      InterfaceCustomization.storageKey,
      () => appdata.updateSettings((settings) {
        settings[InterfaceCustomization.storageKey] = value;
      }, sync: false),
      onSaved: () {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已保存；导航顺序下次启动生效')));
        }
      },
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _orderEditor(String group, List<String> order, Set<String>? hidden) =>
      ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: order.length,
        onReorder: (oldIndex, newIndex) {
          if (savingSettings) return;
          setState(() {
            if (newIndex > oldIndex) newIndex--;
            order.insert(newIndex, order.removeAt(oldIndex));
          });
        },
        itemBuilder: (context, index) {
          final id = order[index];
          return ListTile(
            key: ValueKey('$group:$id'),
            title: Text(_labels[id] ?? id),
            leading: hidden == null
                ? const Icon(Icons.navigation_outlined)
                : Switch(
                    value: !hidden.contains(id),
                    onChanged: savingSettings
                        ? null
                        : (visible) {
                            setState(() {
                              if (visible) {
                                hidden.remove(id);
                              } else {
                                hidden.add(id);
                              }
                            });
                          },
                  ),
            trailing: ReorderableDragStartListener(
              index: index,
              enabled: !savingSettings,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.drag_handle),
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) => protectSettings(
    Scaffold(
      appBar: AppBar(
        title: const Text('界面与按钮'),
        actions: [
          TextButton(
            onPressed: savingSettings ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('拖动右侧手柄排序，开关控制显示。调整后点击“保存”。仅保存到当前设备。搜索和设置入口始终保留。'),
          ),
          settingsSaveStatus,
          _heading('阅读器工具栏'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('仅显示当前平台和漫画源支持的按钮；自动阅读运行时始终保留停止按钮。'),
          ),
          _orderEditor('toolbar', _toolbar, _hiddenToolbar),
          _heading('主页栏目'),
          _orderEditor('home', _home, _hiddenHome),
          _heading('导航顺序'),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('下次启动生效。主页、收藏、发现和分类始终保留。'),
          ),
          _orderEditor('navigation', _navigation, null),
          _heading('阅读操作与外观'),
          ListTile(
            title: const Text('点击区域、双击和长按'),
            subtitle: const Text('调整中央菜单区域宽度、两侧点击动作及原有阅读设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: savingSettings
                ? null
                : () => context.to(() => const ReaderSettings()),
          ),
          ListTile(
            title: const Text('封面大小与漫画列表'),
            subtitle: const Text('封面大小、详细／简洁布局、进度和状态标签'),
            trailing: const Icon(Icons.chevron_right),
            onTap: savingSettings
                ? null
                : () => context.to(() => const ExploreSettings()),
          ),
          ListTile(
            title: const Text('主题与配色'),
            trailing: const Icon(Icons.chevron_right),
            onTap: savingSettings
                ? null
                : () => context.to(() => const AppearanceSettings()),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('恢复本页默认布局'),
              onPressed: savingSettings
                  ? null
                  : () => setState(
                      () => _load(InterfaceCustomization.read(null)),
                    ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text('恢复默认只调整本页草稿，点击保存后生效；不会重置主题、阅读进度或漫画专属设置。'),
          ),
        ],
      ),
    ),
  );
}
