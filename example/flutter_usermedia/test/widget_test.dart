import 'package:flutter_test/flutter_test.dart';

import 'package:usermedia_example/main.dart';

void main() {
  testWidgets('app builds and shows the title', (tester) async {
    await tester.pumpWidget(const UserMediaApp());
    expect(find.text('dart_usermedia — getUserMedia'), findsOneWidget);
  });
}
