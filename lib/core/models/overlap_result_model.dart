class OverlapResultModel {
  final List<Map<String, dynamic>> windows;
  OverlapResultModel({required this.windows});
  Map<String, dynamic> toFirestore() => {windows: windows};
  factory OverlapResultModel.fromFirestore(Map<String, dynamic> map) {
    return OverlapResultModel(windows: List<Map<String, dynamic>>.from(map[windows] ?? []));
  }
}
