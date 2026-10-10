import 'package:flutter_test/flutter_test.dart';
import 'package:chalbroo/utils/name_utils.dart';

void main() {
  test('firstName shows only the first name, neatly cased', () {
    expect(NameUtils.firstName('SAHIL SHARMA'), 'Sahil');
    expect(NameUtils.firstName('Jay Shah'), 'Jay');
    expect(NameUtils.firstName('  raghu   rokda '), 'Raghu');
    expect(NameUtils.firstName('Madonna'), 'Madonna');
  });

  test('firstName never throws or leaks on odd input', () {
    expect(NameUtils.firstName(''), 'User');
    expect(NameUtils.firstName('   '), 'User');
    expect(NameUtils.firstName('A'), 'A');
  });

  test('initial is the first letter, upper-cased', () {
    expect(NameUtils.initial('sahil'), 'S');
    expect(NameUtils.initial(''), 'U');
  });
}
