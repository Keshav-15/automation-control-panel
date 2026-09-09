import 'package:flutter_boilerplate/src/models/qa/project_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileAppId', () {
    test('JSON round-trip preserves both fields', () {
      const id = MobileAppId(androidApplicationId: 'com.x.dev', iosBundleId: 'com.x.dev.ios');
      final back = MobileAppId.fromJson(id.toJson());
      expect(back.androidApplicationId, 'com.x.dev');
      expect(back.iosBundleId, 'com.x.dev.ios');
    });

    test('isEmpty is true only when both fields are null', () {
      expect(const MobileAppId().isEmpty, isTrue);
      expect(const MobileAppId(androidApplicationId: 'x').isEmpty, isFalse);
    });
  });

  group('SurfaceConfig.appId', () {
    test('defaults to null and round-trips through JSON', () {
      const surface = SurfaceConfig(id: 'android_dev', name: 'Android Dev', icon: '🤖');
      expect(surface.appId, isNull);
      final back = SurfaceConfig.fromJson(surface.toJson());
      expect(back.appId, isNull);
    });

    test('a populated appId survives a JSON round-trip', () {
      const surface = SurfaceConfig(
        id: 'android_dev',
        name: 'Android Dev',
        icon: '🤖',
        appId: MobileAppId(androidApplicationId: 'com.x.dev', iosBundleId: 'com.x.dev.ios'),
      );
      final back = SurfaceConfig.fromJson(surface.toJson());
      expect(back.appId?.androidApplicationId, 'com.x.dev');
      expect(back.appId?.iosBundleId, 'com.x.dev.ios');
    });
  });
}
