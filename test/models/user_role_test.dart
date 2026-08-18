import 'package:attendqr/models/user_role.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserRole.fromMap', () {
    test('parses a well-formed role document', () {
      final role = UserRole.fromMap({
        'name': 'Team Lead',
        'description': 'Leads a squad',
        'permissionIds': ['team.view', 'attendance.manage'],
        'isSystem': false,
        'companyId': 'company-a',
        'level': 7,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'updatedAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
      }, id: 'role-1');

      expect(role.id, 'role-1');
      expect(role.name, 'Team Lead');
      expect(role.description, 'Leads a squad');
      expect(role.permissionIds, ['team.view', 'attendance.manage']);
      expect(role.isSystem, isFalse);
      expect(role.companyId, 'company-a');
      expect(role.level, 7);
      expect(role.createdAt, DateTime(2026, 1, 1));
      expect(role.updatedAt, DateTime(2026, 1, 2));
    });

    test('treats a stringified isSystem as false instead of crashing', () {
      final role = UserRole.fromMap({
        'name': 'Legacy',
        'isSystem': 'true',
      }, id: 'role-2');

      expect(role.isSystem, isFalse);
      expect(role.isSystem, isA<bool>());
    });

    test('parses isSystem booleans correctly', () {
      expect(
        UserRole.fromMap({'isSystem': true}, id: 'r').isSystem,
        isTrue,
      );
      expect(
        UserRole.fromMap({'isSystem': false}, id: 'r').isSystem,
        isFalse,
      );
    });

    test('parses isManagerial booleans correctly', () {
      expect(
        UserRole.fromMap({'isManagerial': true}, id: 'r').isManagerial,
        isTrue,
      );
      expect(
        UserRole.fromMap({'isManagerial': false}, id: 'r').isManagerial,
        isFalse,
      );
      expect(
        UserRole.fromMap({}, id: 'r').isManagerial,
        isFalse,
      );
      expect(
        UserRole.fromMap({'isManagerial': 'true'}, id: 'r').isManagerial,
        isFalse,
      );
    });

    test('defaults missing, string, and double levels to safe ints', () {
      expect(UserRole.fromMap({}, id: 'r').level, 10);
      expect(UserRole.fromMap({'level': 15}, id: 'r').level, 15);
      expect(UserRole.fromMap({'level': 10.0}, id: 'r').level, 10);
      expect(UserRole.fromMap({'level': '12'}, id: 'r').level, 12);
      expect(UserRole.fromMap({'level': 'abc'}, id: 'r').level, 10);
    });

    test('coerces non-string permission ids and tolerates malformed lists', () {
      final mixed = UserRole.fromMap({
        'permissionIds': [1, 'attendance.manage', true],
      }, id: 'r');
      expect(mixed.permissionIds, ['1', 'attendance.manage', 'true']);

      expect(UserRole.fromMap({}, id: 'r').permissionIds, isEmpty);
      expect(
        UserRole.fromMap({'permissionIds': 'not-a-list'}, id: 'r')
            .permissionIds,
        isEmpty,
      );
    });

    test('stringifies name/description and keeps companyId null when absent', () {
      final role = UserRole.fromMap({
        'name': 42,
        'description': true,
        'companyId': 123,
      }, id: 'r');

      expect(role.name, '42');
      expect(role.description, 'true');
      expect(role.companyId, isNull);
    });

    test('leaves timestamps null when missing or malformed', () {
      final role = UserRole.fromMap({'createdAt': 'yesterday'}, id: 'r');

      expect(role.createdAt, isNull);
      expect(role.updatedAt, isNull);
    });
  });
}
