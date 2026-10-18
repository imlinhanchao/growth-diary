import 'package:flutter_test/flutter_test.dart';
import 'package:growth_diary/models/app_config.dart';
import 'package:growth_diary/services/network_service.dart';
import 'package:growth_diary/services/qr_service.dart';

void main() {
  group('WebDavMirror Tests', () {
    test('serialization and deserialization', () {
      final mirror = WebDavMirror(
        url: 'http://192.168.1.100:5005',
        wifiSsid: 'Home-WiFi',
      );

      final json = mirror.toJson();
      expect(json['url'], 'http://192.168.1.100:5005');
      expect(json['wifiSsid'], 'Home-WiFi');

      final restored = WebDavMirror.fromJson(json);
      expect(restored.url, mirror.url);
      expect(restored.wifiSsid, mirror.wifiSsid);
      expect(restored.hasWifiBinding, true);
    });

    test('backward compatibility with raw string', () {
      final restored = WebDavMirror.fromJson('https://dav.example.com');
      expect(restored.url, 'https://dav.example.com');
      expect(restored.wifiSsid, null);
      expect(restored.hasWifiBinding, false);
    });

    test('matchesWifi logic', () {
      final mirror = WebDavMirror(
        url: 'http://192.168.1.100:5005',
        wifiSsid: 'Home_WiFi, Home_WiFi_5G; Home_Guest',
      );

      expect(mirror.matchesWifi('Home_WiFi'), true);
      expect(mirror.matchesWifi('home_wifi'), true);
      expect(mirror.matchesWifi('Home_WiFi_5G'), true);
      expect(mirror.matchesWifi('Home_Guest'), true);
      expect(mirror.matchesWifi('Office_WiFi'), false);
      expect(mirror.matchesWifi(null), false);
      expect(mirror.matchesWifi(''), false);

      final unboundMirror = WebDavMirror(url: 'https://dav.example.com');
      expect(unboundMirror.matchesWifi('Home_WiFi'), false);
      expect(unboundMirror.hasWifiBinding, false);
    });
  });

  group('NetworkService cleanWifiSSID Tests', () {
    test('cleans quoted and unknown SSIDs', () {
      expect(NetworkService.cleanWifiSSID('"MyHome"'), 'MyHome');
      expect(NetworkService.cleanWifiSSID('MyHome'), 'MyHome');
      expect(NetworkService.cleanWifiSSID('"'), null);
      expect(NetworkService.cleanWifiSSID('<unknown ssid>'), null);
      expect(NetworkService.cleanWifiSSID('unknown'), null);
      expect(NetworkService.cleanWifiSSID('0x'), null);
      expect(NetworkService.cleanWifiSSID(null), null);
      expect(NetworkService.cleanWifiSSID('   '), null);
    });
  });

  group('AppConfig Mirror Resolution Tests', () {
    test('getMirrorForWifi and defaultUnboundMirror', () {
      final homeMirror = WebDavMirror(
        url: 'http://192.168.1.100:5005',
        wifiSsid: 'Home_WiFi',
      );
      final officeMirror = WebDavMirror(
        url: 'http://10.0.0.5:5005',
        wifiSsid: 'Office_WiFi',
      );
      final defaultMirror = WebDavMirror(
        url: 'https://cloud.example.com',
      );

      final config = AppConfig(
        webdavUrl: 'https://default.example.com',
        username: 'user',
        password: 'pwd',
        babyName: 'Baby',
        webdavMirrors: [homeMirror, officeMirror, defaultMirror],
      );

      // Connected to Home_WiFi -> should match homeMirror
      expect(config.getMirrorForWifi('Home_WiFi')?.url, 'http://192.168.1.100:5005');
      // Connected to Office_WiFi -> should match officeMirror
      expect(config.getMirrorForWifi('Office_WiFi')?.url, 'http://10.0.0.5:5005');
      // Connected to other WiFi or null -> no WiFi mirror matched
      expect(config.getMirrorForWifi('Other_WiFi'), null);
      expect(config.getMirrorForWifi(null), null);

      // defaultUnboundMirror -> should return the mirror without WiFi configuration
      expect(config.defaultUnboundMirror?.url, 'https://cloud.example.com');
    });

    test('AppConfig fromJson and toJson preserves mirrors', () {
      final config = AppConfig(
        webdavUrl: 'https://cloud.example.com',
        username: 'admin',
        password: '123',
        babyName: 'Baby',
        webdavMirrors: [
          WebDavMirror(url: 'http://192.168.1.100:5005', wifiSsid: 'Home_WiFi'),
          WebDavMirror(url: 'https://cloud.example.com'),
        ],
      );

      final json = config.toJson();
      final restored = AppConfig.fromJson(json);

      expect(restored.webdavMirrors.length, 2);
      expect(restored.webdavMirrors[0].url, 'http://192.168.1.100:5005');
      expect(restored.webdavMirrors[0].wifiSsid, 'Home_WiFi');
      expect(restored.webdavMirrors[1].url, 'https://cloud.example.com');
      expect(restored.webdavMirrors[1].wifiSsid, null);
    });

    test('QRService encrypts and decrypts mirrors with wifi bindings', () {
      final config = AppConfig(
        id: 'test_baby_id',
        babyName: 'Test Baby',
        webdavUrl: 'https://cloud.example.com',
        username: 'user',
        password: 'pwd',
        webdavMirrors: [
          WebDavMirror(url: 'http://192.168.50.100:5005', wifiSsid: 'Home-WiFi, Home-5G'),
          WebDavMirror(url: 'https://cloud.example.com'),
        ],
      );

      final qrData = QRService.generateEncryptedQRData(config);
      expect(qrData, isNotEmpty);

      final decoded = QRService.decodeEncryptedQRData(qrData);
      expect(decoded, isNotNull);
      expect(decoded!.webdavMirrors.length, 2);
      expect(decoded.webdavMirrors[0].url, 'http://192.168.50.100:5005');
      expect(decoded.webdavMirrors[0].wifiSsid, 'Home-WiFi, Home-5G');
      expect(decoded.webdavMirrors[0].matchesWifi('Home-WiFi'), true);
      expect(decoded.webdavMirrors[1].url, 'https://cloud.example.com');
      expect(decoded.webdavMirrors[1].hasWifiBinding, false);
    });
  });
}
