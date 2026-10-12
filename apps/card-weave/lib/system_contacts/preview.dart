import 'package:flutter/cupertino.dart';

import '../contacts/contact_content.dart';
import '../design.dart';
import 'mapping.dart';

class ImportContactPreview extends StatelessWidget {
  final ImportCandidate candidate;
  const ImportContactPreview(this.candidate, {super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    navigationBar: AppNavigation(title: const Text('导入预览')),
    body: AppSectionScrollView(
      children: [
        if (candidate.error != null)
          AppStatus(candidate.error!, kind: AppStatusKind.error),
        if (candidate.duplicates.isNotEmpty)
          AppStatus(
            '疑似重复，将作为新联系人导入：\n${candidate.duplicates.join('\n')}',
            kind: AppStatusKind.warning,
          ),
        if (candidate.warnings.isNotEmpty)
          AppStatus(candidate.warnings.join('\n'), kind: AppStatusKind.warning),
        ContactContent(candidate.contact, showHero: true),
      ],
    ),
  );
}
