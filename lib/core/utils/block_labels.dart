import 'package:couple_sync/core/models/time_block.dart';

extension TimeBlockTypeLabel on TimeBlockType {
  String get label => switch (this) {
    TimeBlockType.busy => 'Busy',
    TimeBlockType.free => 'Free',
    TimeBlockType.tentative => 'Tentative',
  };
}

extension TimeBlockCategoryLabel on TimeBlockCategory {
  String get label => switch (this) {
    TimeBlockCategory.work => 'Work',
    TimeBlockCategory.study => 'Study',
    TimeBlockCategory.commute => 'Commute',
    TimeBlockCategory.exercise => 'Exercise',
    TimeBlockCategory.social => 'Social',
    TimeBlockCategory.meals => 'Meals',
    TimeBlockCategory.sleep => 'Sleep',
    TimeBlockCategory.personal => 'Personal',
    TimeBlockCategory.other => 'Other',
  };
}

extension TimeBlockVisibilityLabel on TimeBlockVisibility {
  String get label => switch (this) {
    TimeBlockVisibility.bothPartners => 'Both partners',
    TimeBlockVisibility.onlyMe => 'Only me',
  };
}
