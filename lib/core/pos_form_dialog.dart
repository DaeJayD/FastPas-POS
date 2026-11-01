import 'package:flutter/material.dart';

class PosFormField {
  const PosFormField({
    required this.label,
    this.initialValue = '',
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
  });

  final String label, initialValue;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
  final int maxLines;
}

/// The route owns the controllers until its closing animation has finished.
class PosFormDialog extends StatefulWidget {
  const PosFormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.description,
    this.onSave,
    this.errorMessage,
  });

  final String title;
  final String? description;
  final List<PosFormField> fields;
  final Future<void> Function(Map<String, String>)? onSave;
  final String Function(Object)? errorMessage;

  @override
  State<PosFormDialog> createState() => _PosFormDialogState();
}

class _PosFormDialogState extends State<PosFormDialog> {
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;
  late final _controllers = [
    for (final field in widget.fields)
      TextEditingController(text: field.initialValue),
  ];

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    final values = {
      for (var i = 0; i < widget.fields.length; i++)
        widget.fields[i].label: _controllers[i].text.trim(),
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(values);
      if (mounted) Navigator.pop(context, values);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              widget.errorMessage?.call(error) ??
              'Could not save. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.description != null) ...[
                Text(
                  widget.description!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
              ],
              for (var i = 0; i < widget.fields.length; i++) ...[
                if (i > 0) const SizedBox(height: 18),
                TextFormField(
                  key: ValueKey(widget.fields[i].label),
                  controller: _controllers[i],
                  keyboardType: widget.fields[i].keyboardType,
                  enabled: !_saving,
                  maxLines: widget.fields[i].maxLines,
                  textInputAction: widget.fields[i].maxLines > 1
                      ? TextInputAction.newline
                      : i == widget.fields.length - 1
                      ? TextInputAction.done
                      : TextInputAction.next,
                  validator: widget.fields[i].validator,
                  decoration: InputDecoration(
                    labelText: widget.fields[i].label,
                    errorMaxLines: 3,
                  ),
                  onFieldSubmitted:
                      i == widget.fields.length - 1 &&
                          widget.fields[i].maxLines == 1
                      ? (_) => _submit()
                      : null,
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    ),
  );
}
