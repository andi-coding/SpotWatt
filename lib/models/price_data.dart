class PriceData {
  final DateTime startTime;
  final DateTime endTime;
  final double price;

  PriceData({
    required this.startTime,
    required this.endTime,
    required this.price,
  });

  factory PriceData.fromJson(Map<String, dynamic> json) {
    return PriceData(
      startTime: DateTime.fromMillisecondsSinceEpoch(json['start_timestamp']),
      endTime: DateTime.fromMillisecondsSinceEpoch(json['end_timestamp']),
      price: json['marketprice'] / 10.0, // Convert to ct/kWh
    );
  }
}