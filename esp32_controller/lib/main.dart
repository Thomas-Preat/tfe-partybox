import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:esp32_controller/ble_payload.dart';

void main() {
  runApp(const MyApp());
}

final flutterReactiveBle = FlutterReactiveBle();

final serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final charUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");
const targetDeviceName = "ESP32-FFT Ctrl";

const _pairedDeviceIdKey = 'paired_device_id';
const _pairedDeviceNameKey = 'paired_device_name';
const _appLanguageKey = 'app_language';

enum AppLanguage { english, french }

String tr(AppLanguage language, String key) {
  final value = _localizedStrings[language]?[key];
  if (value != null) {
    return value;
  }
  return _localizedStrings[AppLanguage.english]?[key] ?? key;
}

const Map<AppLanguage, Map<String, String>> _localizedStrings = {
  AppLanguage.english: {
    'pairSpeaker': 'Pair Speaker',
    'settings': 'Settings',
    'language': 'Language',
    'english': 'English',
    'french': 'French',
    'scan': 'Scan',
    'stop': 'Stop',
    'pair': 'Pair',
    'unnamedBleDevice': 'Unnamed BLE device',
    'expectedEsp32Controller': 'Expected ESP32 controller',
    'pairedSpeaker': 'Paired Speaker',
    'unpair': 'Unpair',
    'ledControl': 'LED Control',
    'volumeControl': 'Volume Control',
    'connect': 'Connect',
    'disconnect': 'Disconnect',
    'disconnected': 'Disconnected',
    'connectedTo': 'Connected to',
    'modeCategory': 'Mode Category',
    'soundBased': 'Sound Based',
    'notSoundBased': 'Not Sound Based',
    'fftMode': 'STFT Mode',
    'rainbowFft': 'Rainbow STFT',
    'gradientFft': 'Gradient STFT',
    'solidFft': 'Solid STFT',
    'showPeakIndicator': 'Show Peak Indicator',
    'staticMode': 'Static Mode',
    'solidColor': 'Solid Color',
    'gradient': 'Gradient',
    'columnRainbow': 'Column Rainbow',
    'ledColor': 'LED Color',
    'red': 'Red',
    'green': 'Green',
    'blue': 'Blue',
    'ledSensitivity': 'LED Sensitivity',
    'dspToneControls': 'DSP Tone Controls',
    'flat': 'Flat',
    'warm': 'Warm',
    'bright': 'Bright',
    'gainPwm': 'Gain PWM',
    'bassPwm': 'Bass PWM',
    'treblePwm': 'Treble PWM',
    'statusConnecting': 'Connecting...',
    'statusConnected': 'Connected',
    'statusDisconnected': 'Disconnected',
    'statusDisconnecting': 'Disconnecting...',
    'statusConnectedMissingChar': 'Connected but required characteristic was not found',
    'statusConnectionFailedBusy': 'Connection failed: device/stack busy. Wait a moment and retry.',
    'statusConnectionFailedPrefix': 'Connection failed:',
    'statusDisconnectedWaiting': 'Disconnected, waiting for BLE release...',
    'statusRetryIn': 'Device may still be busy, retry in',
    'seconds': 's',
  },
  AppLanguage.french: {
    'pairSpeaker': 'Appairer le haut-parleur',
    'settings': 'Paramètres',
    'language': 'Langue',
    'english': 'Anglais',
    'french': 'Français',
    'scan': 'Scanner',
    'stop': 'Arrêter',
    'pair': 'Appairer',
    'unnamedBleDevice': 'Appareil BLE sans nom',
    'expectedEsp32Controller': 'Contrôleur ESP32 attendu',
    'pairedSpeaker': 'Haut-parleur appairé',
    'unpair': 'Désappairer',
    'ledControl': 'Contrôle LED',
    'volumeControl': 'Contrôle du volume',
    'connect': 'Connecter',
    'disconnect': 'Déconnecter',
    'disconnected': 'Déconnecté',
    'connectedTo': 'Connecté à',
    'modeCategory': 'Catégorie de mode',
    'soundBased': 'Basé sur le son',
    'notSoundBased': 'Non basé sur le son',
    'fftMode': 'Mode STFT',
    'rainbowFft': 'STFT arc-en-ciel',
    'gradientFft': 'STFT dégradé',
    'solidFft': 'STFT couleur fixe',
    'showPeakIndicator': 'Afficher l’indicateur de pic',
    'staticMode': 'Mode statique',
    'solidColor': 'Couleur fixe',
    'gradient': 'Dégradé',
    'columnRainbow': 'Arc-en-ciel colonnes',
    'ledColor': 'Couleur LED',
    'red': 'Rouge',
    'green': 'Vert',
    'blue': 'Bleu',
    'ledSensitivity': 'Sensibilité LED',
    'dspToneControls': 'Contrôles de tonalité DSP',
    'flat': 'Plat',
    'warm': 'Chaud',
    'bright': 'Clair',
    'gainPwm': 'PWM gain',
    'bassPwm': 'PWM basses',
    'treblePwm': 'PWM aigus',
    'statusConnecting': 'Connexion...',
    'statusConnected': 'Connecté',
    'statusDisconnected': 'Déconnecté',
    'statusDisconnecting': 'Deconnexion...',
    'statusConnectedMissingChar': 'Connecté mais la caractéristique requise est introuvable',
    'statusConnectionFailedBusy': 'Échec connexion: appareil/pile occupé. Attendez puis réessayez.',
    'statusConnectionFailedPrefix': 'Échec connexion:',
    'statusDisconnectedWaiting': 'Déconnecté, attente libération BLE...',
    'statusRetryIn': 'Appareil possiblement occupé, réessayez dans',
    'seconds': 's',
  },
};

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _storage = const FlutterSecureStorage();
  String? pairedDeviceId;
  String? pairedDeviceName;
  AppLanguage appLanguage = AppLanguage.english;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPairedDevice();
  }

  Future<void> _loadPairedDevice() async {
    final deviceId = await _storage.read(key: _pairedDeviceIdKey);
    final deviceName = await _storage.read(key: _pairedDeviceNameKey);
    final savedLanguage = await _storage.read(key: _appLanguageKey);
    setState(() {
      pairedDeviceId = deviceId;
      pairedDeviceName = deviceName;
      appLanguage = savedLanguage == 'fr' ? AppLanguage.french : AppLanguage.english;
      isLoading = false;
    });
  }

  Future<void> _setLanguage(AppLanguage language) async {
    await _storage.write(key: _appLanguageKey, value: language == AppLanguage.french ? 'fr' : 'en');
    if (!mounted) return;
    setState(() {
      appLanguage = language;
    });
  }

  Future<void> _pairDevice(DiscoveredDevice device) async {
    await _storage.write(key: _pairedDeviceIdKey, value: device.id);
    await _storage.write(key: _pairedDeviceNameKey, value: device.name);

    setState(() {
      pairedDeviceId = device.id;
      pairedDeviceName = device.name;
    });
  }

  Future<void> _unpairDevice() async {
    await _storage.delete(key: _pairedDeviceIdKey);
    await _storage.delete(key: _pairedDeviceNameKey);

    setState(() {
      pairedDeviceId = null;
      pairedDeviceName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : (pairedDeviceId == null
              ? PairingPage(
                  onPair: _pairDevice,
                  language: appLanguage,
                  onLanguageChanged: _setLanguage,
                )
              : DevicePage(
                  pairedDeviceId: pairedDeviceId!,
                  pairedDeviceName: pairedDeviceName,
                  onUnpair: _unpairDevice,
                  language: appLanguage,
                  onLanguageChanged: _setLanguage,
                )),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.onPair,
    required this.language,
    required this.onLanguageChanged,
  });

  final Future<void> Function(DiscoveredDevice device) onPair;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  List<DiscoveredDevice> devices = [];
  StreamSubscription<DiscoveredDevice>? scanSub;
  bool isScanning = false;

  void upsertScannedDevice(DiscoveredDevice device) {
    final existingIndex = devices.indexWhere((existing) => existing.id == device.id);

    if (existingIndex == -1) {
      setState(() => devices.add(device));
      return;
    }

    final existingDevice = devices[existingIndex];
    final shouldUpdate = existingDevice.name != device.name || existingDevice.rssi != device.rssi;

    if (!shouldUpdate) {
      return;
    }

    setState(() {
      devices[existingIndex] = device.name.isNotEmpty
          ? device
          : DiscoveredDevice(
              id: existingDevice.id,
              name: existingDevice.name,
              serviceUuids: device.serviceUuids,
              manufacturerData: device.manufacturerData,
              serviceData: device.serviceData,
              rssi: device.rssi,
            );
    });
  }

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  @override
  void dispose() {
    scanSub?.cancel();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  void startScan() {
    scanSub?.cancel();

    setState(() {
      devices.clear();
      isScanning = true;
    });

    scanSub = flutterReactiveBle
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
        )
        .listen((device) {
      debugPrint("Found: ${device.name} | ${device.id}");
      upsertScannedDevice(device);
    }, onError: (e) {
      debugPrint("Scan error: $e");
      setState(() => isScanning = false);
    });
  }

  void stopScan() {
    scanSub?.cancel();
    setState(() => isScanning = false);
  }

  Future<void> pairDevice(DiscoveredDevice device) async {
    await widget.onPair(device);
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(language, 'pairSpeaker')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: tr(language, 'settings'),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LanguageSettingsPage(
                    language: language,
                    onLanguageChanged: widget.onLanguageChanged,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isScanning ? null : startScan,
                    child: Text(tr(language, 'scan')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isScanning ? stopScan : null,
                    child: Text(tr(language, 'stop')),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: devices.map((d) {
                final displayName = d.name.isEmpty ? tr(language, 'unnamedBleDevice') : d.name;
                final isTargetDevice = d.name == targetDeviceName;
                return ListTile(
                  title: Text(displayName),
                  subtitle: Text(isTargetDevice ? "${d.id}\n${tr(language, 'expectedEsp32Controller')}" : d.id),
                  isThreeLine: isTargetDevice,
                  trailing: ElevatedButton(
                    onPressed: () => pairDevice(d),
                    child: Text(tr(language, 'pair')),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class DevicePage extends StatefulWidget {
  const DevicePage({
    super.key,
    required this.pairedDeviceId,
    required this.pairedDeviceName,
    required this.onUnpair,
    required this.language,
    required this.onLanguageChanged,
  });

  final String pairedDeviceId;
  final String? pairedDeviceName;
  final Future<void> Function() onUnpair;
  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  StreamSubscription<ConnectionStateUpdate>? connectionSub;
  Timer? keepAliveTimer;
  Timer? _pendingSend;
  DateTime? _lastSendTime;
  QualifiedCharacteristic? bleChar;
  DateTime? reconnectAvailableAt;
  String statusMessage = 'statusDisconnected';

  int r = 255, g = 0, b = 0;
  int volume = 50;
  int category = 0;  // 0=Sound-based, 1=Not sound-based
  int subMode = 0;   // 0-2 depending on category
  bool showPeak = true;  // for sound-based modes
  int gain = 128;
  int bass = 128;
  int treble = 128;

  bool isConnected = false;
  bool _isPickingColor = false;

  bool get isBleBusy {
    if (reconnectAvailableAt == null) return false;
    return DateTime.now().isBefore(reconnectAvailableAt!);
  }

  int get reconnectWaitSeconds {
    if (reconnectAvailableAt == null) return 0;
    final ms = reconnectAvailableAt!.difference(DateTime.now()).inMilliseconds;
    if (ms <= 0) return 0;
    return ((ms + 999) / 1000).floor();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    keepAliveTimer?.cancel();
    _pendingSend?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    connectionSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopKeepAlive();
    }
  }

  void _startKeepAlive() {
    keepAliveTimer?.cancel();
    keepAliveTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isConnected) return;
      sendData();
    });
  }

  void _stopKeepAlive() {
    keepAliveTimer?.cancel();
    keepAliveTimer = null;
  }

  void connectToPairedDevice() {
    if (isBleBusy) {
      setState(() {
        statusMessage = 'statusBusyRetry';
      });
      return;
    }

    connectionSub?.cancel();
    setState(() {
      statusMessage = 'statusConnecting';
    });

    connectionSub = flutterReactiveBle.connectToDevice(
      id: widget.pairedDeviceId,
    ).listen((state) async {
      if (state.connectionState == DeviceConnectionState.connecting) {
        setState(() => statusMessage = 'statusConnecting');
        return;
      }

      if (state.connectionState == DeviceConnectionState.connected) {
        try {
            await flutterReactiveBle.discoverAllServices(widget.pairedDeviceId);
            final services =
              await flutterReactiveBle.getDiscoveredServices(widget.pairedDeviceId);

          final hasTargetChar = services.any(
            (s) =>
                s.id == serviceUuid &&
                s.characteristics.any((c) => c.id == charUuid),
          );

          if (!hasTargetChar) {
            throw Exception('Required BLE characteristic not found');
          }

          bleChar = QualifiedCharacteristic(
            serviceId: serviceUuid,
            characteristicId: charUuid,
            deviceId: widget.pairedDeviceId,
          );

          setState(() {
            isConnected = true;
            statusMessage = 'statusConnected';
          });

          await sendData();
          _startKeepAlive();
        } catch (e) {
          _stopKeepAlive();
          setState(() {
            isConnected = false;
            bleChar = null;
            statusMessage = 'statusConnectedMissingChar';
          });
        }
      } else if (state.connectionState == DeviceConnectionState.disconnecting) {
        _stopKeepAlive();
        setState(() => statusMessage = 'statusDisconnecting');
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _stopKeepAlive();
        setState(() {
          isConnected = false;
          bleChar = null;
          statusMessage = 'statusDisconnected';
        });
      }
    }, onError: (e) {
      _stopKeepAlive();
      final errorText = e.toString().toLowerCase();
      final likelyBusy = errorText.contains("133") ||
          errorText.contains("busy") ||
          errorText.contains("already") ||
          errorText.contains("gatt");

      setState(() {
        isConnected = false;
        bleChar = null;
        statusMessage = likelyBusy ? 'statusConnectionFailedBusy' : 'statusConnectionFailed:$e';
      });
    });
  }

  void disconnect() {
    _stopKeepAlive();
    connectionSub?.cancel();
    connectionSub = null;
    reconnectAvailableAt = DateTime.now().add(const Duration(seconds: 2));

    setState(() {
      isConnected = false;
      bleChar = null;
      statusMessage = 'statusDisconnectedWaiting';
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || isConnected) return;
      setState(() {
        statusMessage = 'statusDisconnected';
      });
    });
  }

  String _resolveStatusText(AppLanguage language) {
    if (statusMessage == 'statusBusyRetry') {
      return '${tr(language, 'statusRetryIn')} ${reconnectWaitSeconds}${tr(language, 'seconds')}';
    }
    if (statusMessage.startsWith('statusConnectionFailed:')) {
      final detail = statusMessage.substring('statusConnectionFailed:'.length);
      return '${tr(language, 'statusConnectionFailedPrefix')} $detail';
    }
    return tr(language, statusMessage);
  }

  void _scheduleSend() {
    _pendingSend?.cancel();
    final now = DateTime.now();
    final elapsedMs = _lastSendTime == null
        ? 9999
        : now.difference(_lastSendTime!).inMilliseconds;
    if (elapsedMs >= 30) {
      sendData();
    } else {
      _pendingSend = Timer(Duration(milliseconds: 30 - elapsedMs), sendData);
    }
  }

  Future<void> sendData() async {
    if (!isConnected || bleChar == null) return;

    _lastSendTime = DateTime.now();
    final payload = encodeBleControlPacket(
      category: category,
      subMode: subMode,
      red: r,
      green: g,
      blue: b,
      volume: volume,
      showPeak: showPeak,
      gain: gain,
      bass: bass,
      treble: treble,
    );
    try {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        bleChar!,
        value: payload,
      );
    } catch (e) {
      debugPrint("Write error: $e");
    }
  }

  Widget _buildColorPreset(String label, int nr, int ng, int nb) {
    return Expanded(
      child: ElevatedButton(
        onPressed: isConnected
            ? () {
                _setLedColor(Color.fromARGB(255, nr, ng, nb));
              }
            : null,
        child: Text(label),
      ),
    );
  }

  void _setLedColor(Color color) {
    setState(() {
      r = (color.r * 255.0).round().clamp(0, 255);
      g = (color.g * 255.0).round().clamp(0, 255);
      b = (color.b * 255.0).round().clamp(0, 255);
    });
    _scheduleSend();
  }

  Widget _buildLabeledSlider({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text("$label: $value"),
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          onChanged: isConnected ? onChanged : null,
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    final language = widget.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(tr(language, 'modeCategory')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isConnected ? () { setState(() { category = 0; }); sendData(); } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: category == 0 ? Colors.blue : Colors.grey,
                  ),
                  child: Text(tr(language, 'soundBased')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isConnected ? () { setState(() { category = 1; }); sendData(); } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: category == 1 ? Colors.blue : Colors.grey,
                  ),
                  child: Text(tr(language, 'notSoundBased')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSoundModeSelector() {
    final language = widget.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(tr(language, 'fftMode')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 0); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 0 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'rainbowFft')),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 1); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 1 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'gradientFft')),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 2); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 2 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'solidFft')),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(tr(language, 'showPeakIndicator')),
              const SizedBox(width: 8),
              Switch(
                value: showPeak,
                onChanged: isConnected
                    ? (v) { setState(() => showPeak = v); sendData(); }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStaticModeSelector() {
    final language = widget.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(tr(language, 'staticMode')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 0); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 0 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'solidColor')),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 1); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 1 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'gradient')),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 2); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 2 ? Colors.blue : Colors.grey,
                ),
                child: Text(tr(language, 'columnRainbow')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDspPreset(String label, int newGain, int newBass, int newTreble) {
    return Expanded(
      child: ElevatedButton(
        onPressed: isConnected
            ? () {
                setState(() {
                  gain = newGain;
                  bass = newBass;
                  treble = newTreble;
                });
                sendData();
              }
            : null,
        child: Text(label),
      ),
    );
  }

  Widget _buildLedTab() {
    final language = widget.language;
    return ListView(
      physics: _isPickingColor ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 12),
        _buildCategorySelector(),
        const SizedBox(height: 12),
        if (category == 0) _buildSoundModeSelector(),
        if (category == 1) _buildStaticModeSelector(),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "${tr(language, 'ledColor')}: R$r G$g B$b",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SimpleColorWheel(
            color: Color.fromARGB(255, r, g, b),
            enabled: isConnected,
            onColorChanged: _setLedColor,
            onInteractionStart: () {
              if (_isPickingColor) return;
              setState(() => _isPickingColor = true);
            },
            onInteractionEnd: () {
              if (!_isPickingColor) return;
              setState(() => _isPickingColor = false);
            },
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _buildColorPreset(tr(language, 'red'), 255, 0, 0),
              const SizedBox(width: 8),
              _buildColorPreset(tr(language, 'green'), 0, 255, 0),
              const SizedBox(width: 8),
              _buildColorPreset(tr(language, 'blue'), 0, 0, 255),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeTab() {
    final language = widget.language;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 12),
        _buildLabeledSlider(
          label: tr(language, 'ledSensitivity'),
          value: volume,
          min: 0,
          max: 100,
          onChanged: (v) {
            setState(() => volume = v.toInt());
            _scheduleSend();
          },
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(tr(language, 'dspToneControls')),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _buildDspPreset(tr(language, 'flat'), 128, 128, 128),
              const SizedBox(width: 8),
              _buildDspPreset(tr(language, 'warm'), 150, 180, 105),
              const SizedBox(width: 8),
              _buildDspPreset(tr(language, 'bright'), 150, 110, 190),
            ],
          ),
        ),
        _buildLabeledSlider(
          label: tr(language, 'gainPwm'),
          value: gain,
          min: 0,
          max: 255,
          onChanged: (v) {
            setState(() => gain = v.toInt());
            _scheduleSend();
          },
        ),
        _buildLabeledSlider(
          label: tr(language, 'bassPwm'),
          value: bass,
          min: 0,
          max: 255,
          onChanged: (v) {
            setState(() => bass = v.toInt());
            _scheduleSend();
          },
        ),
        _buildLabeledSlider(
          label: tr(language, 'treblePwm'),
          value: treble,
          min: 0,
          max: 255,
          onChanged: (v) {
            setState(() => treble = v.toInt());
            _scheduleSend();
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.pairedDeviceName?.isNotEmpty == true
              ? widget.pairedDeviceName!
              : tr(language, 'pairedSpeaker')),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: tr(language, 'settings'),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LanguageSettingsPage(
                      language: language,
                      onLanguageChanged: widget.onLanguageChanged,
                    ),
                  ),
                );
              },
            ),
            TextButton(
              onPressed: () async {
                disconnect();
                await widget.onUnpair();
              },
              child: Text(tr(language, 'unpair')),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: tr(language, 'ledControl'), icon: const Icon(Icons.lightbulb_outline)),
              Tab(text: tr(language, 'volumeControl'), icon: const Icon(Icons.equalizer)),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: isConnected ? null : connectToPairedDevice,
                        child: Text(tr(language, 'connect')),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isConnected ? disconnect : null,
                        child: Text(tr(language, 'disconnect')),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  isConnected
                      ? '${tr(language, 'connectedTo')} ${widget.pairedDeviceName?.isNotEmpty == true ? widget.pairedDeviceName! : widget.pairedDeviceId}'
                      : tr(language, 'disconnected'),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_resolveStatusText(language)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TabBarView(
                  physics: _isPickingColor ? const NeverScrollableScrollPhysics() : null,
                  children: [
                    _buildLedTab(),
                    _buildVolumeTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SimpleColorWheel extends StatelessWidget {
  const SimpleColorWheel({
    super.key,
    required this.color,
    required this.enabled,
    required this.onColorChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
  });

  final Color color;
  final bool enabled;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;

  Color _colorFromOffset(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final radius = size.shortestSide / 2;
    final distance = math.sqrt(dx * dx + dy * dy).clamp(0.0, radius);
    final saturation = (distance / radius).clamp(0.0, 1.0);
    final hue = ((math.atan2(dy, dx) * 180 / math.pi) + 360) % 360;
    return HSVColor.fromAHSV(1, hue, saturation, 1).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: IgnorePointer(
        ignoring: !enabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wheelSize = math.min(constraints.maxWidth, 300.0);
            return Center(
              child: GestureDetector(
                onTapDown: (details) {
                  onInteractionStart?.call();
                  onColorChanged(_colorFromOffset(details.localPosition, Size.square(wheelSize)));
                },
                onTapUp: (_) => onInteractionEnd?.call(),
                onTapCancel: () => onInteractionEnd?.call(),
                onPanStart: (details) {
                  onInteractionStart?.call();
                  onColorChanged(_colorFromOffset(details.localPosition, Size.square(wheelSize)));
                },
                onPanUpdate: (details) {
                  onColorChanged(_colorFromOffset(details.localPosition, Size.square(wheelSize)));
                },
                onPanEnd: (_) => onInteractionEnd?.call(),
                onPanCancel: () => onInteractionEnd?.call(),
                child: SizedBox(
                  width: wheelSize,
                  height: wheelSize,
                  child: CustomPaint(
                    painter: _ColorWheelPainter(color: color),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;

    final huePaint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xFFFF0000),
          Color(0xFFFFFF00),
          Color(0xFF00FF00),
          Color(0xFF00FFFF),
          Color(0xFF0000FF),
          Color(0xFFFF00FF),
          Color(0xFFFF0000),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final saturationPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, saturationPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black26;
    canvas.drawCircle(center, radius, borderPaint);

    final hsv = HSVColor.fromColor(color);
    final angle = hsv.hue * math.pi / 180;
    final indicatorRadius = hsv.saturation * radius;
    final indicator = Offset(
      center.dx + math.cos(angle) * indicatorRadius,
      center.dy + math.sin(angle) * indicatorRadius,
    );

    final knobBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;
    final knobFill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    canvas.drawCircle(indicator, 10, knobBorder);
    canvas.drawCircle(indicator, 8, knobFill);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({
    super.key,
    required this.language,
    required this.onLanguageChanged,
  });

  final AppLanguage language;
  final Future<void> Function(AppLanguage language) onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(language, 'settings')),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(tr(language, 'language')),
          ),
          RadioListTile<AppLanguage>(
            value: AppLanguage.english,
            groupValue: language,
            title: Text(tr(language, 'english')),
            onChanged: (value) async {
              if (value == null) return;
              await onLanguageChanged(value);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
          RadioListTile<AppLanguage>(
            value: AppLanguage.french,
            groupValue: language,
            title: Text(tr(language, 'french')),
            onChanged: (value) async {
              if (value == null) return;
              await onLanguageChanged(value);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}