import 'package:flutter/cupertino.dart';

import '../theme.dart';
import '../tokens.dart';

class AppInput extends StatelessWidget {
  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool labelVisible;
  final int minLines;
  final bool multiline;
  final bool inline;
  final FocusNode? focusNode;
  const AppInput({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.labelVisible = true,
    this.minLines = 1,
    this.multiline = false,
    this.inline = false,
    this.focusNode,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          labelVisible &&
          (minLines > 1 ||
              label.length > 6 ||
              MediaQuery.textScalerOf(context).scale(16) > 22 ||
              constraints.maxWidth < 260);
      final textStyle = AppTheme.of(context).text.bodyLarge;
      final lineHeight =
          MediaQuery.textScalerOf(context).scale(textStyle.fontSize!) *
          textStyle.height!;
      // CupertinoTextFormFieldRow keeps 7 points of inner text-field padding.
      final inlinePadding = ((AppTokens.row - lineHeight) / 2 - 7).clamp(
        0.0,
        double.infinity,
      );
      final input = Semantics(
        label: label,
        child: CupertinoTextFormFieldRow(
          key: ValueKey('input-$label'),
          initialValue: initialValue,
          focusNode: focusNode,
          textInputAction: minLines > 1 || multiline
              ? TextInputAction.newline
              : TextInputAction.next,
          onFieldSubmitted: minLines > 1 || multiline
              ? null
              : (_) => FocusScope.of(context).nextFocus(),
          controller: controller,
          prefix: labelVisible && !stacked
              ? SizedBox(
                  width: 68,
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.of(context).colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : null,
          padding: inline
              ? EdgeInsets.symmetric(vertical: inlinePadding)
              : AppTokens.rowPadding,
          placeholder: labelVisible ? null : label,
          style: AppTheme.of(context).text.bodyLarge,
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          keyboardType: keyboardType,
          minLines: minLines,
          maxLines: minLines > 1 || multiline ? null : 1,
          obscureText: obscureText,
          enableSuggestions: !obscureText,
          autocorrect: false,
        ),
      );
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: inline
              ? 0
              : minLines > 1
              ? AppTokens.notes
              : AppTokens.row,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (stacked)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: AppTheme.of(context).text.bodySmall,
                  ),
                ),
              ),
            input,
          ],
        ),
      );
    },
  );
}

class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool autofocus;
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    this.autofocus = false,
  });
  @override
  Widget build(BuildContext context) => CupertinoSearchTextField(
    controller: controller,
    autofocus: autofocus,
    placeholder: '搜索',
    onChanged: onChanged,
    onSuffixTap: onClear,
    style: AppTheme.of(context).text.bodyLarge,
    padding: const EdgeInsets.all(AppTokens.small),
    backgroundColor: AppTheme.of(context).colors.surfaceContainerHighest,
  );
}

class AppSelectableText extends StatefulWidget {
  final String data;
  final TextStyle? style;
  const AppSelectableText(this.data, {super.key, this.style});
  @override
  State<AppSelectableText> createState() => _AppSelectableTextState();
}

class _AppSelectableTextState extends State<AppSelectableText> {
  late final controller = TextEditingController(text: widget.data);
  @override
  void didUpdateWidget(covariant AppSelectableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) controller.text = widget.data;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoTextField(
    controller: controller,
    readOnly: true,
    showCursor: false,
    maxLines: null,
    padding: EdgeInsets.zero,
    decoration: null,
    style: widget.style ?? AppTheme.of(context).text.bodyLarge,
  );
}
