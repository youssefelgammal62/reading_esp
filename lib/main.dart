import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(ESPApp());
}

class ESPApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Data Receiver',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: BluetoothScanner(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BluetoothScanner extends StatefulWidget {
  @override
  _BluetoothScannerState createState() => _BluetoothScannerState();
}

class _BluetoothScannerState extends State<BluetoothScanner> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _valueSubscription;

  final Uuid serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  final Uuid characteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

  String _receivedData = "No value yet";
  bool _isScanning = false;
  bool _isConnected = false;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    // Optionally request permissions on startup
    _requestPermissions();
  }

  Future<bool> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    bool allGranted = true;

    statuses.forEach((permission, status) {
      if (!status.isGranted) {
        allGranted = false;
      }
    });

    if (!allGranted) {
      print("One or more permissions denied");
    }

    return allGranted;
  }

  void _startScan() async {
    print('Scanning...');

    // Ensure permissions are granted before scanning
    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      print("Permissions not granted. Cannot start scan.");
      setState(() {
        _isScanning = false;
      });
      return;
    }

    setState(() {
      _isScanning = true;
      _receivedData = "No value yet";
    });

    _scanSubscription = _ble.scanForDevices(withServices: [serviceUuid]).listen(
      (device) {
        print("Found device: ${device.name}");
        if (device.name == "ESP32_BLE") {
          print("Found ESP32: ${device.name}");
          _connectToDevice(device.id);
          _stopScan();
        }
      },
      onError: (error) {
        print("Scan error: $error");
        _stopScan();
      },
    );
  }

  void _stopScan() {
    _scanSubscription?.cancel();
    setState(() {
      _isScanning = false;
    });
    print("Scan stopped");
  }

  void _connectToDevice(String deviceId) {
    print('Connecting to device...');
    _deviceId = deviceId;
    _connectionSubscription = _ble.connectToDevice(id: deviceId).listen(
      (connectionState) {
        switch (connectionState.connectionState) {
          case DeviceConnectionState.connecting:
            print("Connecting to ESP32...");
            break;
          case DeviceConnectionState.connected:
            print("Connected to ESP32");
            setState(() {
              _isConnected = true;
            });
            _subscribeToCharacteristic();
            break;
          case DeviceConnectionState.disconnecting:
            print("Disconnecting from ESP32...");
            break;
          case DeviceConnectionState.disconnected:
            print("Disconnected from ESP32");
            setState(() {
              _isConnected = false;
              _receivedData = "No value yet";
            });
            _connectionSubscription?.cancel();
            _valueSubscription?.cancel();
            break;
        }
      },
      onError: (error) {
        print("Connection error: $error");
        setState(() {
          _isConnected = false;
        });
        _connectionSubscription?.cancel();
        _valueSubscription?.cancel();
      },
    );
  }

  void _subscribeToCharacteristic() {
    if (_deviceId == null) return;
    print('Subscribing to characteristic...');
    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: _deviceId!,
    );

    _valueSubscription = _ble.subscribeToCharacteristic(characteristic).listen(
      (data) {
        final value = String.fromCharCodes(data);
        setState(() {
          _receivedData = value;
        });
        print("Received data: $_receivedData");
      },
      onError: (error) {
        print("Characteristic subscription error: $error");
      },
    );
    print('Subscription started');
  }

  void _disconnectDevice() {
    _connectionSubscription?.cancel();
    _valueSubscription?.cancel();
    setState(() {
      _isConnected = false;
      _receivedData = "No value yet";
      _deviceId = null;
    });
    print("Disconnected from device");
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    _valueSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ESP32 Data Receiver"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            !_isConnected
                ? ElevatedButton(
                    onPressed: _isScanning ? null : _startScan,
                    child: const Text("Start Scanning"),
                  )
                : ElevatedButton(
                    onPressed: _disconnectDevice,
                    child: const Text("Disconnect"),
                  ),
            const SizedBox(height: 20),
            Text(
              "Received Data:\n$_receivedData",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
