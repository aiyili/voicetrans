import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:voicetrans/app_state.dart';
import 'package:voicetrans/languages.dart';
import 'package:voicetrans/main.dart';

/// 真机/模拟器集成测试：App 能启动，且离线翻译核心链路（原生 ML Kit）可用。
/// 在 iOS 模拟器与 Android 模拟器上运行：
///   `flutter test integration_test/app_test.dart -d <deviceId>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'App 启动 + 原生离线翻译链路可用',
    (tester) async {
      final state = AppState();
      await state.loadAll();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const VoiceTransApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 2));

      // 1) 主界面正常渲染
      expect(find.text('实时翻译'), findsOneWidget);
      expect(find.text('历史'), findsWidgets);
      expect(find.text('设置'), findsWidgets);

      // 2) 真实调用原生 ML Kit：下载模型（首次需要网络）并翻译
      final en = langByCode('english');
      final zh = langByCode('chinese');
      await state.translator.ensureModels(en, zh);

      final out1 = await state.translator.translate(en, zh, 'Hello, how are you today?');
      expect(out1.trim(), isNotEmpty, reason: '翻译结果不应为空');
      expect(out1, isNot(equals('Hello, how are you today?')), reason: '应返回中文而非原文');

      final out2 = await state.translator.translate(zh, en, '你好，很高兴见到你。');
      expect(out2.trim(), isNotEmpty);
      expect(out2, isNot(equals('你好，很高兴见到你。')));

      // 3) 模型状态查询正常（此前 NPE/MissingPlugin 的确切调用路径）
      final downloaded = await state.translator.isModelDownloaded(en);
      expect(downloaded, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
