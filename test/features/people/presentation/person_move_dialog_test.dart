import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumovault/core/database/app_database.dart';
import 'package:lumovault/core/database/daos/face_dao.dart';
import 'package:lumovault/features/people/presentation/screens/person_detail_screen.dart';

PersonWithCount _person(int id, {String? name, int photos = 1}) =>
    PersonWithCount(
      person: PersonRow(
        id: id,
        name: name,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        centroidEmbedding: const [],
        centroidModel: 'test-model',
      ),
      faceCount: photos,
      photoCount: photos,
    );

void main() {
  group('showMoveTargetDialog', () {
    late List<PersonWithCount> others;

    setUp(() {
      others = [_person(7, name: 'Ada', photos: 3), _person(9, photos: 2)];
    });

    /// Opens the dialog and returns a getter for the value it resolved to.
    Future<int? Function()> openDialog(WidgetTester tester) async {
      int? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showMoveTargetDialog(context, others);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('"New person" option resolves to the sentinel', (tester) async {
      final getResult = await openDialog(tester);

      await tester.tap(find.text('New person'));
      await tester.pumpAndSettle();

      expect(
        getResult(),
        newPersonSentinel,
        reason: 'choosing New person must be a distinct non-null result',
      );
    });

    testWidgets('an existing person option resolves to its id', (tester) async {
      final getResult = await openDialog(tester);

      await tester.tap(find.text('Ada (3 photos)'));
      await tester.pumpAndSettle();

      expect(getResult(), 7);
    });

    testWidgets('dismissing without choosing resolves to null', (tester) async {
      final getResult = await openDialog(tester);

      // Tap the scrim (top-left corner is outside the centered dialog).
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(
        getResult(),
        isNull,
        reason:
            'a dismissal must be null so the caller aborts — the old code '
            'let dismissal and "New person" share null, moving photos by '
            'accident',
      );
    });
  });
}
