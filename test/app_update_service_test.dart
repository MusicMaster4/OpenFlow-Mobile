import 'package:flutter_test/flutter_test.dart';
import 'package:voxora/src/services/app_update_service.dart';

void main() {
  Map<String, Object> manifest({
    String channel = 'testing',
    int versionCode = 2000012,
  }) => {
    'channel': channel,
    'versionName': channel == 'testing' ? '2.0.1-testing.2' : '2.0.1',
    'versionCode': versionCode,
    'apkUrl':
        'https://github.com/MusicMaster4/OpenFlow-Mobile/releases/download/v2.0.1/openflow.apk',
    'sha256': List.filled(64, 'a').join(),
  };

  test('accepts a newer update from the installed channel', () {
    final update = AvailableAppUpdate.fromMap(
      manifest(),
      expectedChannel: 'testing',
      installedVersionCode: 2000011,
    );

    expect(update.channel, 'testing');
    expect(update.versionCode, 2000012);
  });

  test('rejects a manifest from the other channel', () {
    expect(
      () => AvailableAppUpdate.fromMap(
        manifest(channel: 'stable'),
        expectedChannel: 'testing',
        installedVersionCode: 2000011,
      ),
      throwsFormatException,
    );
  });

  test('rejects an older or replayed version code', () {
    expect(
      () => AvailableAppUpdate.fromMap(
        manifest(versionCode: 2000011),
        expectedChannel: 'testing',
        installedVersionCode: 2000011,
      ),
      throwsFormatException,
    );
  });
}
