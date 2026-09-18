import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:voicetrans/app_state.dart';
import 'package:voicetrans/main.dart';

void main() {
  testWidgets('应用可正常构建并显示主导航', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const VoiceTransApp(),
      ),
    );
    await tester.pump();

    expect(find.text('实时翻译'), findsOneWidget);
    expect(find.text('历史'), findsWidgets);
    expect(find.text('设置'), findsWidgets);
    expect(find.text('声译通'), findsOneWidget);
  });

  testWidgets('语言对与开关初始状态正确', (tester) async {
    final state = AppState();
    expect(state.sourceLang.code, 'english');
    expect(state.targetLang.code, 'chinese');
    expect(state.saveAudio, isTrue);
    expect(state.keepAwake, isTrue);
    expect(state.sameLanguage, isFalse);
    expect(state.isBusy, isFalse);
  });
}
