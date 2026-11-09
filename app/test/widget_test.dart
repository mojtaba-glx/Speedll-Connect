import 'package:flutter_test/flutter_test.dart';
import 'package:speedll_connect_app/main.dart';

void main() {
  testWidgets('shows Speedll Connect preview and disconnected state',
      (tester) async {
    await tester.pumpWidget(const SpeedllConnectApp());

    expect(find.text('Speedll Connect'), findsOneWidget);
    expect(find.text('قطع شده'), findsOneWidget);
    expect(find.text('افزودن اشتراک'), findsOneWidget);
  });
}
