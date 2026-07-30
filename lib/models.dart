enum ExecutionPrivilege { normal, administrator }

enum ActionType { application, shell }

class DesktopApplication {
  const DesktopApplication({
    required this.id,
    required this.name,
    required this.executable,
    required this.defaultArguments,
    required this.iconPath,
    required this.desktopFile,
  });

  final String id;
  final String name;
  final String executable;
  final List<String> defaultArguments;
  final String iconPath;
  final String desktopFile;
}

class LaunchpadAction {
  const LaunchpadAction({
    required this.id,
    required this.name,
    required this.executable,
    required this.arguments,
    required this.actionType,
    required this.shellCommand,
    required this.iconPath,
    required this.workingDirectory,
    required this.privilege,
    required this.requireConfirmation,
    required this.enabled,
  });

  final String id;
  final String name;
  final String executable;
  final List<String> arguments;
  final ActionType actionType;
  final String shellCommand;
  final String iconPath;
  final String workingDirectory;
  final ExecutionPrivilege privilege;
  final bool requireConfirmation;
  final bool enabled;

  factory LaunchpadAction.fromApplication(DesktopApplication app) {
    return LaunchpadAction(
      id: app.id,
      name: app.name,
      executable: app.executable,
      arguments: app.defaultArguments,
      actionType: ActionType.application,
      shellCommand: '',
      iconPath: app.iconPath,
      workingDirectory: '',
      privilege: ExecutionPrivilege.normal,
      requireConfirmation: false,
      enabled: true,
    );
  }

  factory LaunchpadAction.fromJson(Map<String, dynamic> json) {
    return LaunchpadAction(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      executable: json['executable'] as String? ?? '',
      arguments:
          (json['arguments'] as List? ?? const [])
              .map((value) => '$value')
              .toList(),
      actionType: ActionType.values.firstWhere(
        (value) => value.name == json['actionType'],
        orElse: () => ActionType.application,
      ),
      shellCommand: json['shellCommand'] as String? ?? '',
      iconPath: json['iconPath'] as String? ?? '',
      workingDirectory: json['workingDirectory'] as String? ?? '',
      privilege: ExecutionPrivilege.values.firstWhere(
        (value) => value.name == json['privilege'],
        orElse: () => ExecutionPrivilege.normal,
      ),
      requireConfirmation: json['requireConfirmation'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'executable': executable,
    'arguments': arguments,
    'actionType': actionType.name,
    'shellCommand': shellCommand,
    'iconPath': iconPath,
    'workingDirectory': workingDirectory,
    'privilege': privilege.name,
    'requireConfirmation': requireConfirmation,
    'enabled': enabled,
  };

  LaunchpadAction copyWith({
    String? name,
    String? executable,
    List<String>? arguments,
    ActionType? actionType,
    String? shellCommand,
    String? iconPath,
    String? workingDirectory,
    ExecutionPrivilege? privilege,
    bool? requireConfirmation,
    bool? enabled,
  }) {
    return LaunchpadAction(
      id: id,
      name: name ?? this.name,
      executable: executable ?? this.executable,
      arguments: arguments ?? this.arguments,
      actionType: actionType ?? this.actionType,
      shellCommand: shellCommand ?? this.shellCommand,
      iconPath: iconPath ?? this.iconPath,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      privilege: privilege ?? this.privilege,
      requireConfirmation: requireConfirmation ?? this.requireConfirmation,
      enabled: enabled ?? this.enabled,
    );
  }
}
