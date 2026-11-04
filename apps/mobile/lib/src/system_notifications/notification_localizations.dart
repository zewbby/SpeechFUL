import 'package:flutter/widgets.dart';

import '../localization/app_localizations.dart';
import 'notification_models.dart';

/// Titles are platform-owned. Free-form moderation reasons remain verbatim.
String systemNoticeBody(BuildContext context, SystemNotice notice) {
  if (notice.kind == 'REPORT_PROGRESS' && notice.body == '提交举报不代表认定违规。') {
    return hhText(context, '提交举报不代表认定违规。');
  }
  if (notice.kind == 'REPORT_RESULT' &&
      notice.state == 'REVERSED' &&
      notice.body == '原处理经复核撤销。') {
    return hhText(context, '原处理经复核撤销。');
  }
  return notice.body;
}
