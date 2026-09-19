import 'package:flutter_test/flutter_test.dart';
import 'package:shiraztyres_driver/models/driver.dart';

/// Two questions that used to be one.
///
/// *Is the form finished?* belongs to the account screen, and blocks nothing.
/// *Has the office approved this account?* is the only thing that decides
/// whether a shift can be started — the API refuses `driver/online` on exactly
/// that, and nothing else.
Driver build(Map<String, dynamic> extra) => Driver.fromJson(<String, dynamic>{
      'id': 1,
      'name': 'Sam Okonkwo',
      'phone': '07700900401',
      'verification_status': 'pending',
      'vehicles': <dynamic>[
        <String, dynamic>{'id': 1, 'plate': 'AB12CDE', 'is_primary': true},
      ],
      'documents': <dynamic>[],
      'missing_documents': <dynamic>[],
      ...extra,
    });

void main() {
  test('an approved technician takes shifts with the form unfinished', () {
    final driver = build(<String, dynamic>{
      'verification_status': 'approved',
      'name': '',
      'vehicles': <dynamic>[],
      'missing_documents': <dynamic>['insurance'],
    });

    expect(driver.isApproved, isTrue, reason: 'the shift switch is shown on this');
    expect(driver.onboardingComplete, isFalse, reason: 'and the account screen still asks');
  });

  test('a finished form is not approval', () {
    final driver = build(<String, dynamic>{});
    expect(driver.onboardingComplete, isTrue);
    expect(driver.isApproved, isFalse, reason: 'no shift switch until the office acts');
  });

  test('what is outstanding is said in words, not API slugs', () {
    final driver = build(<String, dynamic>{
      'name': '',
      'vehicles': <dynamic>[],
      'missing_documents': <dynamic>['insurance', 'right_to_work'],
    });

    expect(driver.outstanding, <String>[
      'your name',
      'your van',
      'an insurance certificate',
      'proof of right to work',
    ]);
  });

  test('nothing is outstanding once it is all in', () {
    expect(build(<String, dynamic>{}).outstanding, isEmpty);
  });

  test('an unknown document type is still named rather than dropped', () {
    final driver = build(<String, dynamic>{'missing_documents': <dynamic>['dbs_check']});
    expect(driver.outstanding, <String>['dbs check']);
  });

  test('the three standings the shift screen tells apart', () {
    expect(build(<String, dynamic>{}).isPending, isTrue);
    expect(build(<String, dynamic>{'verification_status': 'suspended'}).isSuspended, isTrue);
    expect(build(<String, dynamic>{'verification_status': 'rejected'}).isRejected, isTrue);
    expect(build(<String, dynamic>{'verification_status': 'approved'}).isPending, isFalse);
  });
}
