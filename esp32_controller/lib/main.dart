import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

final flutterReactiveBle = FlutterReactiveBle();

final serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final charUuid = Uuid.parse("abcd1234-5678-90ab-cdef-1234567890ab");
const targetDeviceName = "ESP32-FFT Ctrl";

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? pairedDeviceId;
  String? pairedDeviceName;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPairedDevice();
  }

  Future<void> _loadPairedDevice() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      pairedDeviceId = prefs.getString('paired_device_id');
      pairedDeviceName = prefs.getString('paired_device_name');
      isLoading = false;
    });
  }

  Future<void> _pairDevice(DiscoveredDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paired_device_id', device.id);
    await prefs.setString('paired_device_name', device.name);

    setState(() {
      pairedDeviceId = device.id;
      pairedDeviceName = device.name;
    });
  }

  Future<void> _unpairDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('paired_device_id');
    await prefs.remove('paired_device_name');

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
              ? PairingPage(onPair: _pairDevice)
              : DevicePage(
                  pairedDeviceId: pairedDeviceId!,
                  pairedDeviceName: pairedDeviceName,
                  onUnpair: _unpairDevice,
                )),
      debugShowCheckedModeBanner: false,
    );
  }
}

class PairingPage extends StatefulWidget {
  const PairingPage({super.key, required this.onPair});

  final Future<void> Function(DiscoveredDevice device) onPair;

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
          withServices: const [], // scan EVERYTHING
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
    return Scaffold(
      appBar: AppBar(title: const Text("Pair Speaker")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isScanning ? null : startScan,
                    child: const Text("Scan"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: isScanning ? stopScan : null,
                    child: const Text("Stop"),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: devices.map((d) {
                final displayName = d.name.isEmpty ? "Unnamed BLE device" : d.name;
                final isTargetDevice = d.name == targetDeviceName;
                return ListTile(
                  title: Text(displayName),
                  subtitle: Text(isTargetDevice ? "${d.id}\nExpected ESP32 controller" : d.id),
                  isThreeLine: isTargetDevice,
                  trailing: ElevatedButton(
                    onPressed: () => pairDevice(d),
                    child: const Text("Pair"),
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
  });

  final String pairedDeviceId;
  final String? pairedDeviceName;
  final Future<void> Function() onUnpair;

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> with WidgetsBindingObserver {
  StreamSubscription<ConnectionStateUpdate>? connectionSub;
  Timer? keepAliveTimer;
  QualifiedCharacteristic? bleChar;
  DateTime? reconnectAvailableAt;
  String statusMessage = "Disconnected";

  int r = 255, g = 0, b = 0;
  int volume = 50;
  int category = 0;  // 0=Sound-based, 1=Not sound-based
  int subMode = 0;   // 0-2 depending on category
  bool showPeak = true;  // for sound-based modes
  int gain = 128;
  int bass = 128;
  int treble = 128;

  bool isConnected = false;

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
        statusMessage = "Device may still be busy, retry in ${reconnectWaitSeconds}s";
      });
      return;
    }

    connectionSub?.cancel();
    setState(() {
      statusMessage = "Connecting...";
    });

    connectionSub = flutterReactiveBle.connectToDevice(
      id: widget.pairedDeviceId,
    ).listen((state) async {
      if (state.connectionState == DeviceConnectionState.connecting) {
        setState(() => statusMessage = "Connecting...");
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
            statusMessage = "Connected";
          });

          await sendData();
          _startKeepAlive();
        } catch (e) {
          _stopKeepAlive();
          setState(() {
            isConnected = false;
            bleChar = null;
            statusMessage = "Connected but required characteristic was not found";
          });
        }
      } else if (state.connectionState == DeviceConnectionState.disconnecting) {
        _stopKeepAlive();
        setState(() => statusMessage = "Disconnecting...");
      } else if (state.connectionState == DeviceConnectionState.disconnected) {
        _stopKeepAlive();
        setState(() {
          isConnected = false;
          bleChar = null;
          statusMessage = "Disconnected";
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
        statusMessage = likelyBusy
            ? "Connection failed: device/stack busy. Wait a moment and retry."
            : "Connection failed: $e";
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
      statusMessage = "Disconnected, waiting for BLE release...";
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || isConnected) return;
      setState(() {
        statusMessage = "Disconnected";
      });
    });
  }

  Future<void> sendData() async {
    if (!isConnected || bleChar == null) return;

    int flags = showPeak ? 0x01 : 0x00;
    try {
      await flutterReactiveBle.writeCharacteristicWithResponse(
        bleChar!,
        value: [category, subMode, r, g, b, volume, flags, gain, bass, treble],
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
                setState(() {
                  r = nr;
                  g = ng;
                  b = nb;
                });
                sendData();
              }
            : null,
        child: Text(label),
      ),
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("Mode Category"),
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
                  child: const Text("Sound Based"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isConnected ? () { setState(() { category = 1; }); sendData(); } : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: category == 1 ? Colors.blue : Colors.grey,
                  ),
                  child: const Text("Not Sound Based"),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSoundModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("FFT Mode"),
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
                child: const Text("Rainbow FFT"),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 1); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 1 ? Colors.blue : Colors.grey,
                ),
                child: const Text("Gradient FFT"),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 2); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 2 ? Colors.blue : Colors.grey,
                ),
                child: const Text("Solid FFT"),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text("Show Peak Indicator"),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text("Static Mode"),
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
                child: const Text("Solid Color"),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 1); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 1 ? Colors.blue : Colors.grey,
                ),
                child: const Text("Gradient"),
              ),
              ElevatedButton(
                onPressed: isConnected
                    ? () { setState(() => subMode = 2); sendData(); }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: subMode == 2 ? Colors.blue : Colors.grey,
                ),
                child: const Text("Column Rainbow"),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pairedDeviceName?.isNotEmpty == true
            ? widget.pairedDeviceName!
            : "Paired Speaker"),
        actions: [
          TextButton(
            onPressed: () async {
              disconnect();
              await widget.onUnpair();
            },
            child: const Text("Unpair"),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isConnected ? null : connectToPairedDevice,
                      child: const Text("Connect"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isConnected ? disconnect : null,
                      child: const Text("Disconnect"),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                isConnected
                    ? "Connected to ${widget.pairedDeviceName?.isNotEmpty == true ? widget.pairedDeviceName! : widget.pairedDeviceId}"
                    : "Non connecté",
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(statusMessage),
            ),

            const SizedBox(height: 12),
            _buildCategorySelector(),
            const SizedBox(height: 12),
            if (category == 0) _buildSoundModeSelector(),
            if (category == 1) _buildStaticModeSelector(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildColorPreset("Red", 255, 0, 0),
                  const SizedBox(width: 8),
                  _buildColorPreset("Green", 0, 255, 0),
                  const SizedBox(width: 8),
                  _buildColorPreset("Blue", 0, 0, 255),
                ],
              ),
            ),

            _buildLabeledSlider(
              label: "Red",
              value: r,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => r = v.toInt());
                sendData();
              },
            ),

            _buildLabeledSlider(
              label: "Green",
              value: g,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => g = v.toInt());
                sendData();
              },
            ),

            _buildLabeledSlider(
              label: "Blue",
              value: b,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => b = v.toInt());
                sendData();
              },
            ),

            _buildLabeledSlider(
              label: "LED Sensitivity",
              value: volume,
              min: 0,
              max: 100,
              onChanged: (v) {
                setState(() => volume = v.toInt());
                sendData();
              },
            ),

            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text("DSP Tone Controls"),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _buildDspPreset("Flat", 128, 128, 128),
                  const SizedBox(width: 8),
                  _buildDspPreset("Warm", 150, 180, 105),
                  const SizedBox(width: 8),
                  _buildDspPreset("Bright", 150, 110, 190),
                ],
              ),
            ),

            _buildLabeledSlider(
              label: "Gain PWM",
              value: gain,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => gain = v.toInt());
                sendData();
              },
            ),

            _buildLabeledSlider(
              label: "Bass PWM",
              value: bass,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => bass = v.toInt());
                sendData();
              },
            ),

            _buildLabeledSlider(
              label: "Treble PWM",
              value: treble,
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => treble = v.toInt());
                sendData();
              },
            ),
          ],
        ),
      ),
    );
  }
}