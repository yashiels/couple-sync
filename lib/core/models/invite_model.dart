class InviteModel {
  final String code;
  final String createdByUid;
  final String? coupleId;
  InviteModel({required this.code, required this.createdByUid, this.coupleId});
  Map<String, dynamic> toFirestore() => {code: code, createdByUid: createdByUid, coupleId: coupleId};
  factory InviteModel.fromFirestore(Map<String, dynamic> map){
    return InviteModel(code: map[code], createdByUid: map[createdByUid], coupleId: map[coupleId]);
  }
}
