class ShellyDevice {
  final String id;
  final String name;
  final String type;
  final bool isOnline;
  bool isOn;

  ShellyDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.isOnline,
    required this.isOn,
  });
}