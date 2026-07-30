import 'dart:convert';
import 'dart:io';

import '../models.dart';

class ApplicationScanner {
  Future<List<DesktopApplication>> scan() async {
    if (Platform.isWindows) return _scanWindows();
    if (Platform.isMacOS) return _scanMacOS();
    return _scanLinux();
  }

  Future<List<DesktopApplication>> _scanLinux() async {
    final iconIndex = await _buildIconIndex();
    final applications = <String, DesktopApplication>{};
    for (final directory in _applicationDirectories()) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith('.desktop')) continue;
        final app = await _parseDesktopFile(entity, iconIndex);
        if (app != null) applications[app.id] = app;
      }
    }
    final result =
        applications.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return result;
  }

  Future<List<DesktopApplication>> _scanWindows() async {
    final applications = <String, DesktopApplication>{};
    try {
      final result = await Process.run('powershell.exe', const [
        '-NoProfile',
        '-Command',
        r'Get-StartApps | Select-Object Name,AppID | ConvertTo-Json -Compress',
      ]);
      if (result.exitCode != 0) return const [];
      final decoded = jsonDecode('${result.stdout}');
      final entries = decoded is List ? decoded : <dynamic>[decoded];
      for (final entry in entries.whereType<Map<String, dynamic>>()) {
        final name = '${entry['Name'] ?? ''}'.trim();
        final appId = '${entry['AppID'] ?? ''}'.trim();
        if (name.isEmpty || appId.isEmpty) continue;
        final id = _safeId(appId);
        applications[id] = DesktopApplication(
          id: id,
          name: name,
          executable: 'explorer.exe',
          defaultArguments: ['shell:AppsFolder\\$appId'],
          iconPath: '',
          desktopFile: appId,
        );
      }
    } catch (_) {}
    final result =
        applications.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return result;
  }

  Future<List<DesktopApplication>> _scanMacOS() async {
    final applications = <String, DesktopApplication>{};
    final home = Platform.environment['HOME'] ?? '';
    final roots = <Directory>[
      Directory('/Applications'),
      Directory('/System/Applications'),
      if (home.isNotEmpty) Directory('$home/Applications'),
    ];
    for (final root in roots) {
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list()) {
          if (entity is! Directory || !entity.path.endsWith('.app')) continue;
          final bundleName =
              entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
          final name = bundleName.substring(0, bundleName.length - 4);
          final id = _safeId(entity.path);
          applications[id] = DesktopApplication(
            id: id,
            name: name,
            executable: '/usr/bin/open',
            defaultArguments: ['-a', entity.path],
            iconPath: '',
            desktopFile: entity.path,
          );
        }
      } catch (_) {}
    }
    final result =
        applications.values.toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    return result;
  }

  List<Directory> _applicationDirectories() {
    final home = Platform.environment['HOME'] ?? '';
    final dataDirs =
        Platform.environment['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
    return <Directory>[
      if (home.isNotEmpty) Directory('$home/.local/share/applications'),
      for (final path in dataDirs.split(':')) Directory('$path/applications'),
    ];
  }

  Future<DesktopApplication?> _parseDesktopFile(
    File file,
    Map<String, String> icons,
  ) async {
    try {
      final lines = await file.readAsLines();
      final values = <String, String>{};
      var inDesktopEntry = false;
      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.startsWith('[')) {
          inDesktopEntry = line == '[Desktop Entry]';
          continue;
        }
        if (!inDesktopEntry || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        values[line.substring(0, separator)] = line.substring(separator + 1);
      }
      if (values['Type'] != 'Application' ||
          _isTrue(values['Hidden']) ||
          _isTrue(values['NoDisplay']) ||
          values['Exec'] == null) {
        return null;
      }
      final command =
          splitCommandLine(
            values['Exec']!,
          ).where((part) => !RegExp(r'^%[a-zA-Z]$').hasMatch(part)).toList();
      if (command.isEmpty) return null;
      final iconName = values['Icon'] ?? '';
      final id = file.uri.pathSegments.last.replaceFirst('.desktop', '');
      return DesktopApplication(
        id: id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_'),
        name:
            values['Name[zh_CN]'] ?? values['Name[zh]'] ?? values['Name'] ?? id,
        executable: command.first,
        defaultArguments: command.skip(1).toList(),
        iconPath: iconName.startsWith('/') ? iconName : icons[iconName] ?? '',
        desktopFile: file.path,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> _buildIconIndex() async {
    final home = Platform.environment['HOME'] ?? '';
    final roots = <Directory>[
      Directory('/usr/share/pixmaps'),
      Directory('/usr/share/icons/hicolor'),
      Directory('/usr/share/icons/Adwaita'),
      if (home.isNotEmpty) Directory('$home/.local/share/icons'),
      if (home.isNotEmpty) Directory('$home/.icons'),
    ];
    final result = <String, String>{};
    final scores = <String, int>{};
    for (final root in roots) {
      if (!await root.exists()) continue;
      try {
        await for (final entity in root.list(recursive: true)) {
          if (entity is! File) continue;
          final lower = entity.path.toLowerCase();
          if (!lower.endsWith('.png') && !lower.endsWith('.svg')) {
            continue;
          }
          final filename = entity.uri.pathSegments.last;
          final dot = filename.lastIndexOf('.');
          final name = dot > 0 ? filename.substring(0, dot) : filename;
          final score = _iconScore(entity.path);
          if (score > (scores[name] ?? -1)) {
            scores[name] = score;
            result[name] = entity.path;
          }
        }
      } catch (_) {}
    }
    return result;
  }

  int _iconScore(String path) {
    var score = path.endsWith('.png') ? 20 : 15;
    for (final size in const [512, 256, 128, 96, 64, 48]) {
      if (path.contains('/${size}x$size/')) {
        score += 100 - (size - 128).abs() ~/ 8;
        break;
      }
    }
    return score;
  }

  bool _isTrue(String? value) => value?.toLowerCase() == 'true';

  String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
}

List<String> splitCommandLine(String input) {
  final result = <String>[];
  final current = StringBuffer();
  String? quote;
  var escaped = false;
  for (var index = 0; index < input.length; index++) {
    final character = input[index];
    if (escaped) {
      current.write(character);
      escaped = false;
    } else if (character == r'\') {
      escaped = true;
    } else if (quote != null) {
      if (character == quote) {
        quote = null;
      } else {
        current.write(character);
      }
    } else if (character == '"' || character == "'") {
      quote = character;
    } else if (character.trim().isEmpty) {
      if (current.isNotEmpty) {
        result.add(current.toString());
        current.clear();
      }
    } else {
      current.write(character);
    }
  }
  if (current.isNotEmpty) result.add(current.toString());
  return result;
}
