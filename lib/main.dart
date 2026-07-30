import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'services/application_scanner.dart';
import 'services/host_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(900, 680),
    minimumSize: Size(720, 520),
    center: true,
    title: 'Launchpad 上位机',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setPreventClose(true);
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const LaunchpadHostApp());
}

class LaunchpadHostApp extends StatelessWidget {
  const LaunchpadHostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Launchpad 上位机',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HostPage(),
    );
  }
}

class HostPage extends StatefulWidget {
  const HostPage({super.key});

  @override
  State<HostPage> createState() => _HostPageState();
}

class _HostPageState extends State<HostPage> with WindowListener, TrayListener {
  final HostController _controller = HostController();
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _controller.confirmExecution = _confirmExecution;
    _controller.addListener(_changed);
    _controller.initialize();
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(_initializeTray());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _controller.disconnect();
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeTray() async {
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    final iconPath =
        Platform.isMacOS
            ? '$executableDirectory/../Frameworks/App.framework/Resources/'
                'flutter_assets/assets/tray_icon.png'
            : '$executableDirectory/data/flutter_assets/assets/'
                '${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}';
    await trayManager.setIcon(iconPath, isTemplate: Platform.isMacOS);
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: '显示 Launchpad 上位机'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
  }

  @override
  Future<void> onWindowClose() async {
    if (_exiting || !mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('关闭 Launchpad 上位机'),
            content: const Text('退出后开发板上的电脑图标会变为离线。保留在状态栏可继续接收开发板操作。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('取消'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'tray'),
                icon: const Icon(Icons.minimize),
                label: const Text('保留在状态栏'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'exit'),
                child: const Text('退出程序'),
              ),
            ],
          ),
    );
    if (choice == 'tray') {
      await windowManager.hide();
    } else if (choice == 'exit') {
      await _exitApplication();
    }
  }

  Future<void> _exitApplication() async {
    _exiting = true;
    await _controller.disconnect();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      unawaited(_showWindow());
    } else if (menuItem.key == 'exit') {
      unawaited(_exitApplication());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<bool> _confirmExecution(LaunchpadAction action) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('确认执行'),
                content: Text('开发板请求启动“${action.name}”，是否允许？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('允许'),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> _connectionDialog() async {
    final host = TextEditingController(text: _controller.host);
    final token = TextEditingController(text: _controller.token);
    final clientId = TextEditingController(text: _controller.clientId);
    final clientName = TextEditingController(text: _controller.clientName);
    final saved = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('开发板连接设置'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: host,
                    decoration: const InputDecoration(
                      labelText: '开发板 IP',
                      hintText: '192.168.1.100',
                    ),
                  ),
                  TextField(
                    controller: token,
                    maxLength: 4,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: '4 字符令牌'),
                  ),
                  TextField(
                    controller: clientId,
                    decoration: const InputDecoration(
                      labelText: '客户端 ID',
                      helperText: '只允许字母、数字、下划线和连字符',
                    ),
                  ),
                  TextField(
                    controller: clientName,
                    decoration: const InputDecoration(labelText: '电脑显示名称'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存'),
              ),
            ],
          ),
    );
    if (saved == true) {
      await _controller.updateConnection(
        host: host.text,
        token: token.text,
        clientId: clientId.text,
        clientName: clientName.text,
      );
    }
    host.dispose();
    token.dispose();
    clientId.dispose();
    clientName.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final installed =
        _controller.installed
            .where(
              (app) =>
                  _search.isEmpty ||
                  app.name.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Launchpad 上位机'),
          actions: [
            _ConnectionChip(controller: _controller),
            IconButton(
              tooltip: '连接设置',
              onPressed: _connectionDialog,
              icon: const Icon(Icons.settings_ethernet),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_customize), text: '已添加'),
              Tab(icon: Icon(Icons.add_to_photos_outlined), text: '待添加'),
            ],
          ),
        ),
        body: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(_controller.message)),
                    if (_controller.connectionState ==
                        HostConnectionState.disconnected)
                      FilledButton.icon(
                        onPressed: _controller.connect,
                        icon: const Icon(Icons.link),
                        label: const Text('连接'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed:
                            _controller.connectionState ==
                                    HostConnectionState.connected
                                ? _controller.disconnect
                                : null,
                        icon: const Icon(Icons.link_off),
                        label: const Text('断开'),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _AddedActions(
                    controller: _controller,
                    onEdit: (action) => _editAction(action),
                    onCreate: _createAction,
                  ),
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged:
                                    (value) => setState(() => _search = value),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: '搜索本机应用',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _controller.scanning
                                      ? null
                                      : _controller.scanApplications,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重新扫描'),
                            ),
                          ],
                        ),
                      ),
                      if (_controller.scanning) const LinearProgressIndicator(),
                      Expanded(
                        child: _ApplicationGrid(
                          applications: installed,
                          onAdd: (app) async {
                            await _controller.addApplication(app);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已添加 ${app.name}')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editAction(LaunchpadAction action) async {
    final updated = await showDialog<LaunchpadAction>(
      context: context,
      builder: (context) => _ActionEditor(action: action),
    );
    if (updated != null) await _controller.updateAction(updated);
  }

  Future<void> _createAction() async {
    final action = LaunchpadAction(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      name: '自定义操作',
      executable: '',
      arguments: const [],
      actionType: ActionType.shell,
      shellCommand: '',
      iconPath: '',
      workingDirectory: '',
      privilege: ExecutionPrivilege.normal,
      requireConfirmation: true,
      enabled: true,
    );
    final created = await showDialog<LaunchpadAction>(
      context: context,
      builder: (context) => _ActionEditor(action: action, creating: true),
    );
    if (created != null) await _controller.addAction(created);
  }
}

class _ConnectionChip extends StatelessWidget {
  const _ConnectionChip({required this.controller});
  final HostController controller;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (controller.connectionState) {
      HostConnectionState.connected => (Colors.green, '已连接'),
      HostConnectionState.connecting => (Colors.orange, '连接中'),
      HostConnectionState.disconnected => (Colors.grey, '未连接'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Chip(
        avatar: Icon(Icons.circle, size: 12, color: color),
        label: Text(label),
      ),
    );
  }
}

class _ApplicationGrid extends StatelessWidget {
  const _ApplicationGrid({required this.applications, required this.onAdd});
  final List<DesktopApplication> applications;
  final ValueChanged<DesktopApplication> onAdd;

  @override
  Widget build(BuildContext context) {
    if (applications.isEmpty) {
      return const Center(child: Text('没有找到应用'));
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 190,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: applications.length,
      itemBuilder: (context, index) {
        final app = applications[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onAdd(app),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Expanded(child: AppIcon(path: app.iconPath, size: 72)),
                  const SizedBox(height: 8),
                  Text(
                    app.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, size: 16),
                      SizedBox(width: 4),
                      Text('添加'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AddedActions extends StatelessWidget {
  const _AddedActions({
    required this.controller,
    required this.onEdit,
    required this.onCreate,
  });
  final HostController controller;
  final ValueChanged<LaunchpadAction> onEdit;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              const Expanded(child: Text('拖动右侧手柄调整开发板图标顺序')),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('新建自定义操作'),
              ),
            ],
          ),
        ),
        Expanded(
          child:
              controller.actions.isEmpty
                  ? const Center(child: Text('尚未添加操作'))
                  : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    buildDefaultDragHandles: false,
                    itemCount: controller.actions.length,
                    onReorder: controller.reorderAction,
                    itemBuilder: (context, index) {
                      final action = controller.actions[index];
                      return Card(
                        key: ValueKey(action.id),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: AppIcon(path: action.iconPath, size: 42),
                          ),
                          title: Text(action.name),
                          subtitle: Text(
                            '${action.actionType == ActionType.shell ? action.shellCommand : '${action.executable} ${action.arguments.join(' ')}'}'
                            '${action.privilege == ExecutionPrivilege.administrator ? ' · 管理员权限' : ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Switch(
                                value: action.enabled,
                                onChanged:
                                    (value) => controller.updateAction(
                                      action.copyWith(enabled: value),
                                    ),
                              ),
                              IconButton(
                                tooltip: '编辑',
                                onPressed: () => onEdit(action),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: '删除',
                                onPressed:
                                    () => controller.removeAction(action.id),
                                icon: const Icon(Icons.delete_outline),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

class AppIcon extends StatelessWidget {
  const AppIcon({super.key, required this.path, required this.size});
  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Icon(Icons.apps, size: size);
    }
    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(path),
        width: size,
        height: size,
        placeholderBuilder: (_) => Icon(Icons.apps, size: size),
      );
    }
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(Icons.apps, size: size),
    );
  }
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({required this.action, this.creating = false});
  final LaunchpadAction action;
  final bool creating;

  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  late final TextEditingController _name;
  late final TextEditingController _executable;
  late final TextEditingController _arguments;
  late final TextEditingController _shellCommand;
  late final TextEditingController _workingDirectory;
  late final TextEditingController _icon;
  late ExecutionPrivilege _privilege;
  late ActionType _actionType;
  late bool _confirmation;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.action.name);
    _executable = TextEditingController(text: widget.action.executable);
    _arguments = TextEditingController(text: widget.action.arguments.join(' '));
    _shellCommand = TextEditingController(text: widget.action.shellCommand);
    _workingDirectory = TextEditingController(
      text: widget.action.workingDirectory,
    );
    _icon = TextEditingController(text: widget.action.iconPath);
    _privilege = widget.action.privilege;
    _actionType = widget.action.actionType;
    _confirmation = widget.action.requireConfirmation;
    _enabled = widget.action.enabled;
  }

  @override
  void dispose() {
    _name.dispose();
    _executable.dispose();
    _arguments.dispose();
    _shellCommand.dispose();
    _workingDirectory.dispose();
    _icon.dispose();
    super.dispose();
  }

  Future<void> _selectPath(
    TextEditingController controller, {
    bool directory = false,
  }) async {
    try {
      final path =
          directory
              ? await FilePicker.platform.getDirectoryPath(
                dialogTitle: '选择工作目录',
              )
              : (await FilePicker.platform.pickFiles(
                dialogTitle:
                    identical(controller, _icon) ? '选择图标文件' : '选择可执行文件',
                type:
                    identical(controller, _icon)
                        ? FileType.custom
                        : FileType.any,
                allowedExtensions:
                    identical(controller, _icon)
                        ? const ['png', 'svg', 'jpg', 'jpeg', 'ico']
                        : null,
                lockParentWindow: true,
              ))?.files.single.path;
      if (path != null && mounted) {
        setState(() => controller.text = path);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开文件选择器：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.creating ? '新建自定义操作' : '编辑 ${widget.action.name}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '自定义名称'),
              ),
              const SizedBox(height: 12),
              SegmentedButton<ActionType>(
                segments: const [
                  ButtonSegment(
                    value: ActionType.application,
                    icon: Icon(Icons.apps),
                    label: Text('程序与参数'),
                  ),
                  ButtonSegment(
                    value: ActionType.shell,
                    icon: Icon(Icons.terminal),
                    label: Text('Shell 指令'),
                  ),
                ],
                selected: {_actionType},
                onSelectionChanged:
                    (value) => setState(() => _actionType = value.first),
              ),
              if (_actionType == ActionType.application) ...[
                _PathField(
                  controller: _executable,
                  label: '可执行文件',
                  onBrowse: () => _selectPath(_executable),
                ),
                TextField(
                  controller: _arguments,
                  decoration: const InputDecoration(
                    labelText: '启动参数',
                    helperText: '支持空格、单引号、双引号和反斜杠转义',
                  ),
                ),
              ] else
                TextField(
                  controller: _shellCommand,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Shell 指令',
                    hintText: '例如：systemctl restart my-service',
                    helperText: '由 /bin/sh -lc 执行，可使用管道、重定向和环境变量',
                    border: OutlineInputBorder(),
                  ),
                ),
              _PathField(
                controller: _workingDirectory,
                label: '工作目录（可选）',
                onBrowse: () => _selectPath(_workingDirectory, directory: true),
              ),
              _PathField(
                controller: _icon,
                label: '图标文件（PNG 或 SVG）',
                onBrowse: () => _selectPath(_icon),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ExecutionPrivilege>(
                value: _privilege,
                decoration: const InputDecoration(labelText: '执行权限'),
                items: const [
                  DropdownMenuItem(
                    value: ExecutionPrivilege.normal,
                    child: Text('当前用户'),
                  ),
                  DropdownMenuItem(
                    value: ExecutionPrivilege.administrator,
                    child: Text('管理员（执行时由系统弹窗请求授权）'),
                  ),
                ],
                onChanged: (value) => setState(() => _privilege = value!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('每次执行前在电脑上确认'),
                value: _confirmation,
                onChanged: (value) => setState(() => _confirmation = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用并同步到开发板'),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final commandMissing =
                _actionType == ActionType.application
                    ? _executable.text.trim().isEmpty
                    : _shellCommand.text.trim().isEmpty;
            if (_name.text.trim().isEmpty || commandMissing) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('名称和执行内容不能为空')));
              return;
            }
            Navigator.pop(
              context,
              widget.action.copyWith(
                name: _name.text.trim(),
                executable: _executable.text.trim(),
                arguments: splitCommandLine(_arguments.text),
                actionType: _actionType,
                shellCommand: _shellCommand.text.trim(),
                workingDirectory: _workingDirectory.text.trim(),
                iconPath: _icon.text.trim(),
                privilege: _privilege,
                requireConfirmation: _confirmation,
                enabled: _enabled,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _PathField extends StatelessWidget {
  const _PathField({
    required this.controller,
    required this.label,
    required this.onBrowse,
  });
  final TextEditingController controller;
  final String label;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
          ),
        ),
        IconButton(
          tooltip: '浏览',
          onPressed: onBrowse,
          icon: const Icon(Icons.folder_open),
        ),
      ],
    );
  }
}
