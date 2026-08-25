import 'package:deck_master/services/revenue_cat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RevenueCatService', () {
    test('isConfigured is false when placeholder API keys are used', () {
      expect(RevenueCatService.isConfigured, isFalse);
    });

    test('isSupportedPlatform reports true for mobile and macOS', () {
      expect(RevenueCatService.isSupportedPlatform, isTrue);
    });

    test('singleton instance is non-null', () {
      final service1 = RevenueCatService();
      final service2 = RevenueCatService();
      expect(service1, same(service2));
    });

    test('unconfigured service ignores initialize and logOut gracefully', () async {
      final service = RevenueCatService();
      // Should not throw or fail when isConfigured is false
      await service.initialize('test-user-uid');
      await service.logOut();
    });

    test('unconfigured service returns null or false for purchases safely', () async {
      final service = RevenueCatService();
      final offerings = await service.getOfferings();
      expect(offerings, isNull);

      final hasPro = await service.hasPro();
      expect(hasPro, isFalse);

      final restored = await service.restorePurchases();
      expect(restored, isFalse);
    });
  });
}
