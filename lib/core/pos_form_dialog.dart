import 'package:flutter/material.dart';

class PosFormField {
  const PosFormField({
    required this.label,
    this.initialValue = '',
    this.keyboardType,
    this.validator,
  });

  final String label, initialValue;
  final TextInputType? keyboardType;
  final FormFieldValidator<String>? validator;
}

/// The route owns the controllers until its closing animation has finished.
class PosFormDialog extends StatefulWidget {
  const PosFormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.description,
  });

  final String title;
  final String? description;
  final List<PosFormField> fields;

  @override
  State<PosFormDialog> createState() => _PosFormDialogState();
}

class _PosFormDialogState extends State<PosFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _controllers = [
    for (final field in widget.fields)
      TextEditingController(text: field.initialValue),
  ];

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(context, {
      for (var i = 0; i < widget.fields.length; i++)
        widget.fields[i].label: _controllers[i].text.trim(),
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                textInputAction: i == widget.fields.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                validator: widget.fields[i].validator,
                decoration: InputDecoration(
                  labelText: widget.fields[i].label,
                  errorMaxLines: 3,
                ),
                onFieldSubmitted: i == widget.fields.length - 1
                    ? (_) => _submit()
                    : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
