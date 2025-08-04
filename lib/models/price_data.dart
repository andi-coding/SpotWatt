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
  
  Map<String, dynamic> toJson() {
    return {
      'start_timestamp': startTime.millisecondsSinceEpoch,
      'end_timestamp': endTime.millisecondsSinceEpoch,
      'marketprice': price * 10.0, // Convert back from ct/kWh
    };
  }
}