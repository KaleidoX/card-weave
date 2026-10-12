import 'package:flutter/cupertino.dart';

import 'actions.dart';
import '../theme.dart';
import '../tokens.dart';

enum AppStatusKind { info, success, warning, error }

class AppStatus extends StatelessWidget {
  final String message;
  final AppStatusKind kind;
  final VoidCallback? onRetry;
  const AppStatus(
    this.message, {
    super.key,
    this.kind = AppStatusKind.info,
    this.onRetry,
  });
  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final color = switch (kind) {
      AppStatusKind.error => colors.error,
      AppStatusKind.warning => colors.onTertiaryContainer,
      AppStatusKind.success => colors.primary,
      AppStatusKind.info => colors.onSurfaceVariant,
    };
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: AppTokens.pagePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  kind == AppStatusKind.error || kind == AppStatusKind.warning
                      ? CupertinoIcons.exclamationmark_circle
                      : CupertinoIcons.info_circle,
                  size: AppTokens.actionIcon,
                  color: color,
                ),
                const SizedBox(width: AppTokens.small),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: color, fontSize: AppTokens.caption),
                  ),
                ),
              ],
            ),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(onPressed: onRetry, child: const Text('重试')),
              ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  final String title;
  final String? message;
  const AppEmptyState(this.title, {super.key, this.message});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AppTokens.pagePadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: AppTheme.of(context).text.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: AppTokens.small),
            Text(
              message!,
              style: AppTheme.of(context).text.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    ),
  );
}

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: AppTokens.pagePadding,
      child: CupertinoActivityIndicator(),
    ),
  );
}
