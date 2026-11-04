import 'package:flutter/widgets.dart';

import '../localization/app_localizations.dart';

/// Controller-owned status keys are translated when rendered, never when saved.
String messagingUiError(BuildContext context, String source) {
  const prefix = '操作未完成：';
  if (source.startsWith(prefix)) {
    return hhText(
      context,
      '操作未完成：{reason}',
      args: {'reason': hhText(context, source.substring(prefix.length))},
    );
  }
  return hhText(context, source);
}
