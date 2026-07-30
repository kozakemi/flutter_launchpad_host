import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_launchpad_host/main.dart';

void main() {
  testWidgets('shows Launchpad host window', (tester) async {
    await tester.pumpWidget(const LaunchpadHostApp());
    expect(find.text('Launchpad 上位机'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('待添加'), findsOneWidget);
  });
}
