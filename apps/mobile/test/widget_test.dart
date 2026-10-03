import 'package:bombario/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home screen shows the solo button', (tester) async {
    await tester.pumpWidget(const BlastPartyApp());
    expect(find.text('Bombario'), findsOneWidget);
    expect(find.text('Solo'), findsOneWidget);
  });
}
