import 'package:couple_sync/services/firestore_service.dart';
import 'package:couple_sync/services/providers/firestore_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';

@GenerateMocks([FirestoreService])
import 'firestore_provider_test.mocks.dart';

void main() {
  group('firestoreServiceProvider', () {
    test('is a Provider<FirestoreService>', () {
      expect(firestoreServiceProvider, isA<Provider<FirestoreService>>());
    });

    test('can be overridden with a mock', () {
      final mockFirestoreService = MockFirestoreService();

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(mockFirestoreService),
        ],
      );
      addTearDown(container.dispose);

      final service = container.read(firestoreServiceProvider);
      expect(service, same(mockFirestoreService));
    });

    test('returns same instance on multiple reads', () {
      final mockFirestoreService = MockFirestoreService();

      final container = ProviderContainer(
        overrides: [
          firestoreServiceProvider.overrideWithValue(mockFirestoreService),
        ],
      );
      addTearDown(container.dispose);

      final first = container.read(firestoreServiceProvider);
      final second = container.read(firestoreServiceProvider);
      expect(first, same(second));
    });
  });
}
