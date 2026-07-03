import 'package:couple_sync/services/calendar_service.dart';
import 'package:couple_sync/services/providers/calendar_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateMocks([CalendarService])
import 'calendar_provider_test.mocks.dart';

void main() {
  group('calendarServiceProvider', () {
    test('returns a CalendarService instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(calendarServiceProvider, isA<Provider<CalendarService>>());
    });
  });

  group('calendarConnectionProvider', () {
    late MockCalendarService mockCalendarService;

    setUp(() {
      mockCalendarService = MockCalendarService();
    });

    test('returns true when calendar is connected', () async {
      when(mockCalendarService.isConnected).thenAnswer((_) async => true);

      final container = ProviderContainer(
        overrides: [
          calendarServiceProvider.overrideWithValue(mockCalendarService),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(calendarConnectionProvider.future);
      expect(result, isTrue);
      verify(mockCalendarService.isConnected).called(1);
    });

    test('returns false when calendar is not connected', () async {
      when(mockCalendarService.isConnected).thenAnswer((_) async => false);

      final container = ProviderContainer(
        overrides: [
          calendarServiceProvider.overrideWithValue(mockCalendarService),
        ],
      );
      addTearDown(container.dispose);

      final result = await container.read(calendarConnectionProvider.future);
      expect(result, isFalse);
    });
  });

  group('CalendarConnectionNotifier', () {
    late MockCalendarService mockCalendarService;

    setUp(() {
      mockCalendarService = MockCalendarService();
    });

    ProviderContainer createContainer() {
      final container = ProviderContainer(
        overrides: [
          calendarServiceProvider.overrideWithValue(mockCalendarService),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('initial state loads connection status', () async {
      when(mockCalendarService.isConnected).thenAnswer((_) async => true);

      final container = createContainer();

      // Initially loading
      final initialState = container.read(calendarConnectionNotifierProvider);
      expect(initialState, isA<AsyncLoading<bool>>());

      // Wait for load to complete
      await container
          .read(calendarConnectionNotifierProvider.notifier)
          .refresh();

      final state = container.read(calendarConnectionNotifierProvider);
      expect(state, isA<AsyncData<bool>>());
      expect(state.value, isTrue);
    });

    test('initial state loads as false when not connected', () async {
      when(mockCalendarService.isConnected).thenAnswer((_) async => false);

      final container = createContainer();
      await container
          .read(calendarConnectionNotifierProvider.notifier)
          .refresh();

      final state = container.read(calendarConnectionNotifierProvider);
      expect(state.value, isFalse);
    });

    group('connect', () {
      test('returns true and updates state on success', () async {
        when(mockCalendarService.isConnected).thenAnswer((_) async => false);
        when(mockCalendarService.connect()).thenAnswer((_) async => true);

        final container = createContainer();
        // Wait for initial load
        await Future.delayed(Duration.zero);

        final notifier = container.read(
          calendarConnectionNotifierProvider.notifier,
        );
        final result = await notifier.connect();

        expect(result, isTrue);
        final state = container.read(calendarConnectionNotifierProvider);
        expect(state.value, isTrue);
        verify(mockCalendarService.connect()).called(1);
      });

      test(
        'returns false and updates state when connect returns false',
        () async {
          when(mockCalendarService.isConnected).thenAnswer((_) async => false);
          when(mockCalendarService.connect()).thenAnswer((_) async => false);

          final container = createContainer();
          await Future.delayed(Duration.zero);

          final notifier = container.read(
            calendarConnectionNotifierProvider.notifier,
          );
          final result = await notifier.connect();

          expect(result, isFalse);
          final state = container.read(calendarConnectionNotifierProvider);
          expect(state.value, isFalse);
        },
      );

      test('returns false and sets error state on exception', () async {
        when(mockCalendarService.isConnected).thenAnswer((_) async => false);
        when(mockCalendarService.connect()).thenAnswer(
          (_) async => throw const CalendarException(
            code: 'connection-failed',
            message: 'Failed to connect',
          ),
        );

        final container = createContainer();
        await Future.delayed(Duration.zero);

        final notifier = container.read(
          calendarConnectionNotifierProvider.notifier,
        );
        final result = await notifier.connect();

        expect(result, isFalse);
        final state = container.read(calendarConnectionNotifierProvider);
        expect(state, isA<AsyncError<bool>>());
        expect(state.error, isA<CalendarException>());
      });
    });

    group('disconnect', () {
      test('sets state to false on success', () async {
        when(mockCalendarService.isConnected).thenAnswer((_) async => true);
        when(mockCalendarService.disconnect()).thenAnswer((_) async {});

        final container = createContainer();
        await Future.delayed(Duration.zero);

        final notifier = container.read(
          calendarConnectionNotifierProvider.notifier,
        );
        await notifier.disconnect();

        final state = container.read(calendarConnectionNotifierProvider);
        expect(state.value, isFalse);
        verify(mockCalendarService.disconnect()).called(1);
      });

      test('sets error state on exception', () async {
        when(mockCalendarService.isConnected).thenAnswer((_) async => true);
        when(mockCalendarService.disconnect()).thenAnswer(
          (_) async => throw const CalendarException(
            code: 'disconnect-failed',
            message: 'Failed to disconnect',
          ),
        );

        final container = createContainer();
        await Future.delayed(Duration.zero);

        final notifier = container.read(
          calendarConnectionNotifierProvider.notifier,
        );
        await notifier.disconnect();

        final state = container.read(calendarConnectionNotifierProvider);
        expect(state, isA<AsyncError<bool>>());
        expect(state.error, isA<CalendarException>());
      });
    });

    group('refresh', () {
      test('reloads connection state from service', () async {
        var callCount = 0;
        when(mockCalendarService.isConnected).thenAnswer((_) async {
          callCount++;
          return callCount > 1; // false first, true on refresh
        });

        final container = createContainer();
        // Wait for initial load
        await Future.delayed(Duration.zero);

        final notifier = container.read(
          calendarConnectionNotifierProvider.notifier,
        );
        await notifier.refresh();

        final state = container.read(calendarConnectionNotifierProvider);
        expect(state.value, isTrue);
        // isConnected called at least twice: initial + refresh
        verify(mockCalendarService.isConnected).called(greaterThanOrEqualTo(2));
      });
    });
  });

  group('calendarConnectionNotifierProvider', () {
    test('is a StateNotifierProvider of correct types', () {
      expect(
        calendarConnectionNotifierProvider,
        isA<
          StateNotifierProvider<CalendarConnectionNotifier, AsyncValue<bool>>
        >(),
      );
    });
  });
}
