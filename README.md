# Flutter Launchpad Host

Linux 桌面上位机，用于向开发板动态注册 Launchpad 操作。

## 功能

- 扫描 `/usr/share/applications`、`~/.local/share/applications` 等目录中的
  `.desktop` 应用。
- 自动查找 PNG/SVG 应用图标并在待添加页面显示。
- 自定义名称、可执行文件、启动参数、工作目录和图标。
- 新建 Shell 操作，通过 `/bin/sh -lc` 执行管道、重定向和组合命令。
- 创建或编辑图标时可声明普通权限或管理员权限；管理员操作通过
  `pkexec` 调用 Polkit，不保存 sudo 密码。
- 支持执行前确认、单项停用和拖拽排序。
- 通过带令牌的 WebSocket 连接开发板，断线后每 3 秒自动重连。
- 关闭窗口时可选择退出，或隐藏到系统状态栏继续接收开发板操作。
- 配置保存在 `~/.config/flutter-launchpad-host/config.json`。

## 运行

```bash
flutter run -d linux
```

已经构建的 Debug 版本：

```bash
./build/linux/x64/debug/bundle/flutter_launchpad_host
```

先在开发板设置中开启“远程 Web 设置”，然后在上位机右上角连接设置中填写
开发板 IP、4 字符令牌、客户端 ID 和电脑显示名称。

文件选择按钮使用 `zenity`。未安装时仍可直接输入文件或目录路径。

Linux 系统托盘依赖 AppIndicator。Ubuntu/Debian 构建环境可安装：

```bash
sudo apt install libayatana-appindicator3-dev
```

GNOME 桌面可能还需要启用 AppIndicator/KStatusNotifierItem 扩展才能看到状态栏图标。
