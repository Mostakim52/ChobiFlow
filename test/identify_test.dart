import 'package:chobiflow/device_import.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('norm', () {
    test('sdcard and emulated/0 are the same file', () {
      expect(
        DeviceImport.norm('/sdcard/Pictures/a.png'),
        DeviceImport.norm('/storage/emulated/0/Pictures/a.png'),
      );
    });
    test('different files stay different', () {
      expect(
        DeviceImport.norm('/sdcard/Pictures/a.png') ==
            DeviceImport.norm('/sdcard/Pictures/b.png'),
        false,
      );
    });
  });

  group('guessFromText reads content, not filenames', () {
    test('boarding pass text -> travel', () {
      expect(
        DeviceImport.guessFromText(
            'BOARDING PASS BOM to SIN Gate closes 40 min early'),
        'travel',
      );
    });
    test('hotel confirmation -> travel', () {
      expect(
        DeviceImport.guessFromText(
            'HOTEL CONFIRM late checkout 1pm reservation'),
        'travel',
      );
    });
    test('build error log -> work', () {
      expect(
        DeviceImport.guessFromText(
            'Error Gradle daemon ran out of memory exception'),
        'work',
      );
    });
    test('receipt + otp -> personal', () {
      expect(
        DeviceImport.guessFromText(
            'Payment receipt total 1240 your OTP is 8831'),
        'personal',
      );
    });
    test('gibberish filename-style text stays recent', () {
      expect(
        DeviceImport.guessFromText('Screenshot 20261007 201301'),
        'recent',
      );
    });
  });

  group('keywords', () {
    test('top content words win, noise dropped', () {
      final k = DeviceImport.keywords(
          'Flight flight FLIGHT booking hotel booking and the screenshot');
      expect(k.first, 'flight');
      expect(k, contains('booking'));
      expect(k, isNot(contains('and')));
      expect(k, isNot(contains('screenshot')));
    });
    test('empty text -> empty', () {
      expect(DeviceImport.keywords(''), isEmpty);
    });
  });
}
