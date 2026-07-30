import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models.dart';
import 'application_scanner.dart';

enum HostConnectionState { disconnected, connecting, connected }

class HostController extends ChangeNotifier {
  final ApplicationScanner _scanner = ApplicationScanner();
  final List<DesktopApplication> _installed = [];
  final List<LaunchpadAction> _actions = [];
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _manualDisconnect = true;
  bool _scanning = false;
  String _host = '';
  String _token = '';
  String _clientId = 'flutter-desktop';
  String _clientName = Platform.localHostname;
  String _message = '';
  HostConnectionState _connectionState = HostConnectionState.disconnected;

  Future<bool> Function(LaunchpadAction action)? confirmExecution;

  List<DesktopApplication> get installed =>
      List<DesktopApplication>.unmodifiable(_installed);
  List<LaunchpadAction> get actions =>
      List<LaunchpadAction>.unmodifiable(_actions);
  bool get scanning => _scanning;
  String get host => _host;
  String get token => _token;
  String get clientId => _clientId;
  String get clientName => _clientName;
  String get message => _message;
  HostConnectionState get connectionState => _connectionState;

  Future<void> initialize() async {
    await _loadConfiguration();
    await scanApplications();
    if (_host.isNotEmpty && _token.length == 4) {
      unawaited(connect());
    }
  }

  Future<void> scanApplications() async {
    if (_scanning) return;
    _scanning = true;
    _message = '正在扫描本机应用和图标…';
    notifyListeners();
    final result = await _scanner.scan();
    _installed
      ..clear()
      ..addAll(result);
    _scanning = false;
    _message = '发现 ${result.length} 个应用';
    notifyListeners();
  }

  bool get isConnected => _connectionState == HostConnectionState.connected;

  Future<void> updateConnection({
    required String host,
    required String token,
    required String clientId,
    required String clientName,
  }) async {
    _host = host.trim();
    _token = token.trim().toUpperCase();
    _clientId = _safeId(clientId);
    _clientName = clientName.trim();
    await _saveConfiguration();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_connectionState != HostConnectionState.disconnected) return;
    if (_host.isEmpty || _token.length != 4 || _clientId.isEmpty) {
      _message = '请先填写开发板地址、令牌和客户端 ID';
      notifyListeners();
      return;
    }
    _manualDisconnect = false;
    _connectionState = HostConnectionState.connecting;
    _message = '正在连接开发板…';
    notifyListeners();
    try {
      final socket = await WebSocket.connect(
        'ws://$_host:19080/ws/launchpad?token=$_token',
      ).timeout(const Duration(seconds: 5));
      _socket = socket;
      _connectionState = HostConnectionState.connected;
      _message = '已连接开发板';
      socket.listen(
        _handleMessage,
        onDone: () => _disconnected(socket),
        onError: (_) => _disconnected(socket),
        cancelOnError: true,
      );
      await _registerActions();
      notifyListeners();
    } catch (error) {
      _connectionState = HostConnectionState.disconnected;
      final detail = '$error';
      _message =
          detail.contains('status code: 404')
              ? '开发板程序版本过旧：未提供远程 Launchpad 接口，请更新开发板程序'
              : detail.contains('status code: 403')
              ? '连接被拒绝：4 字符令牌不正确或已经更新'
              : '连接失败：$detail';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final socket = _socket;
    _socket = null;
    _connectionState = HostConnectionState.disconnected;
    _message = '已断开连接';
    notifyListeners();
    await socket?.close();
  }

  void _disconnected(WebSocket socket) {
    if (_socket != socket) return;
    _socket = null;
    _connectionState = HostConnectionState.disconnected;
    _message = '与开发板的连接已断开';
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  Future<void> _registerActions() async {
    final socket = _socket;
    if (socket == null) return;
    final registrations = <Map<String, Object>>[];
    for (var index = 0; index < _actions.length; index++) {
      final action = _actions[index];
      if (!action.enabled) continue;
      final item = <String, Object>{
        'id': action.id,
        'name': action.name,
        'order': index,
      };
      final icon = File(action.iconPath);
      if (action.iconPath.isNotEmpty && await icon.exists()) {
        final bytes = await icon.readAsBytes();
        if (bytes.length <= 512 * 1024) {
          item['iconBase64'] = base64Encode(bytes);
          item['iconFormat'] = action.iconPath.split('.').last.toLowerCase();
        }
      }
      registrations.add(item);
    }
    socket.add(
      jsonEncode({
        'type': 'registerActions',
        'clientId': _clientId,
        'clientName': _clientName.isEmpty ? _clientId : _clientName,
        'actions': registrations,
      }),
    );
  }

  void _handleMessage(dynamic rawMessage) {
    if (rawMessage is! String) return;
    try {
      final message = jsonDecode(rawMessage);
      if (message is! Map<String, dynamic>) return;
      if (message['type'] == 'invoke') {
        unawaited(
          _invoke(
            message['actionId'] as String? ?? '',
            message['requestId'] as String? ?? '',
          ),
        );
      } else if (message['type'] == 'registered') {
        _message = '已向开发板注册 ${message['actionCount']} 个按钮';
        notifyListeners();
      } else if (message['type'] == 'error') {
        _message = '${message['message']}';
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _invoke(String actionId, String requestId) async {
    final action = _actions.where((item) => item.id == actionId).firstOrNull;
    if (action == null || !action.enabled) {
      _sendResult(requestId, false, '操作不存在或已禁用');
      return;
    }
    if (action.requireConfirmation &&
        !(await confirmExecution?.call(action) ?? false)) {
      _sendResult(requestId, false, '用户取消执行');
      return;
    }
    try {
      final command = _executionCommand(action);
      final process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory:
            command.usesWorkingDirectory
                ? (action.workingDirectory.isEmpty
                    ? null
                    : action.workingDirectory)
                : null,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      _message = '已启动 ${action.name}，PID ${process.pid}';
      _sendResult(requestId, true, _message);
    } catch (error) {
      _message = '启动 ${action.name} 失败：$error';
      _sendResult(requestId, false, _message);
    }
    notifyListeners();
  }

  _ExecutionCommand _executionCommand(LaunchpadAction action) {
    final isShell = action.actionType == ActionType.shell;
    final baseExecutable =
        isShell
            ? (Platform.isWindows ? 'powershell.exe' : '/bin/sh')
            : action.executable;
    final baseArguments =
        isShell
            ? (Platform.isWindows
                ? <String>['-NoProfile', '-Command', action.shellCommand]
                : <String>['-lc', action.shellCommand])
            : action.arguments;

    if (action.privilege == ExecutionPrivilege.normal) {
      return _ExecutionCommand(baseExecutable, baseArguments, true);
    }
    if (Platform.isWindows) {
      final argumentList = baseArguments.map(_powerShellQuote).join(',');
      final workingDirectory =
          action.workingDirectory.isEmpty
              ? ''
              : ' -WorkingDirectory ${_powerShellQuote(action.workingDirectory)}';
      final script =
          'Start-Process -FilePath ${_powerShellQuote(baseExecutable)}'
          '${baseArguments.isEmpty ? '' : ' -ArgumentList @($argumentList)'}'
          '$workingDirectory -Verb RunAs';
      return _ExecutionCommand('powershell.exe', [
        '-NoProfile',
        '-Command',
        script,
      ], false);
    }
    if (Platform.isMacOS) {
      final command = <String>[
        baseExecutable,
        ...baseArguments,
      ].map(_shellQuote).join(' ');
      final script =
          'do shell script ${_appleScriptQuote(command)} '
          'with administrator privileges';
      return _ExecutionCommand('/usr/bin/osascript', ['-e', script], false);
    }
    return _ExecutionCommand('pkexec', <String>[
      baseExecutable,
      ...baseArguments,
    ], true);
  }

  String _powerShellQuote(String value) => "'${value.replaceAll("'", "''")}'";

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  String _appleScriptQuote(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  void _sendResult(String requestId, bool success, String message) {
    _socket?.add(
      jsonEncode({
        'type': 'result',
        'requestId': requestId,
        'success': success,
        'message': message,
      }),
    );
  }

  Future<void> addApplication(DesktopApplication application) async {
    var id = application.id;
    var suffix = 2;
    while (_actions.any((item) => item.id == id)) {
      id = '${application.id}_${suffix++}';
    }
    _actions.add(LaunchpadAction.fromApplication(application).copyWith());
    if (id != application.id) {
      final last = _actions.removeLast();
      _actions.add(
        LaunchpadAction(
          id: id,
          name: last.name,
          executable: last.executable,
          arguments: last.arguments,
          actionType: last.actionType,
          shellCommand: last.shellCommand,
          iconPath: last.iconPath,
          workingDirectory: last.workingDirectory,
          privilege: last.privilege,
          requireConfirmation: last.requireConfirmation,
          enabled: last.enabled,
        ),
      );
    }
    await _actionsChanged();
  }

  Future<void> updateAction(LaunchpadAction action) async {
    final index = _actions.indexWhere((item) => item.id == action.id);
    if (index < 0) return;
    _actions[index] = action;
    await _actionsChanged();
  }

  Future<void> addAction(LaunchpadAction action) async {
    _actions.add(action);
    await _actionsChanged();
  }

  Future<void> removeAction(String id) async {
    _actions.removeWhere((item) => item.id == id);
    await _actionsChanged();
  }

  Future<void> reorderAction(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final action = _actions.removeAt(oldIndex);
    _actions.insert(newIndex, action);
    await _actionsChanged();
  }

  Future<void> _actionsChanged() async {
    await _saveConfiguration();
    if (isConnected) await _registerActions();
    notifyListeners();
  }

  Directory get _configDirectory {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? Directory.current.path;
      return Directory('$appData/flutter-launchpad-host');
    }
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (Platform.isMacOS) {
      return Directory(
        '$home/Library/Application Support/flutter-launchpad-host',
      );
    }
    final configHome =
        Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    return Directory('$configHome/flutter-launchpad-host');
  }

  Future<void> _loadConfiguration() async {
    try {
      final file = File('${_configDirectory.path}/config.json');
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return;
      _host = json['host'] as String? ?? '';
      _token = json['token'] as String? ?? '';
      _clientId = json['clientId'] as String? ?? _clientId;
      _clientName = json['clientName'] as String? ?? _clientName;
      _actions
        ..clear()
        ..addAll(
          (json['actions'] as List? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(LaunchpadAction.fromJson),
        );
    } catch (error) {
      _message = '读取配置失败：$error';
    }
  }

  Future<void> _saveConfiguration() async {
    await _configDirectory.create(recursive: true);
    await File('${_configDirectory.path}/config.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'host': _host,
        'token': _token,
        'clientId': _clientId,
        'clientName': _clientName,
        'actions': _actions.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
  }

  String _safeId(String value) =>
      value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

class _ExecutionCommand {
  const _ExecutionCommand(
    this.executable,
    this.arguments,
    this.usesWorkingDirectory,
  );

  final String executable;
  final List<String> arguments;
  final bool usesWorkingDirectory;
}
