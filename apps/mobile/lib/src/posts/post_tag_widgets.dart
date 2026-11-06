import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_localizations.dart';
import 'post_controller.dart';
import 'post_tags.dart';

class PostTagChips extends StatelessWidget {
  const PostTagChips({super.key, required this.tags, this.onTap});
  final List<String> tags;
  final ValueChanged<String>? onTap;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    runSpacing: 2,
    children: [
      for (final tag in tags)
        TextButton(
          onPressed: onTap == null ? null : () => onTap!(tag),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 40),
          ),
          child: Text('#$tag'),
        ),
    ],
  );
}

Future<List<String>?> showPostTagPicker(
  BuildContext context,
  PostController controller,
  List<String> selected,
) => showModalBottomSheet<List<String>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PostTagPicker(controller: controller, selected: selected),
);

class _PostTagPicker extends StatefulWidget {
  const _PostTagPicker({required this.controller, required this.selected});
  final PostController controller;
  final List<String> selected;
  @override
  State<_PostTagPicker> createState() => _PostTagPickerState();
}

class _PostTagPickerState extends State<_PostTagPicker> {
  final _input = TextEditingController();
  late final _tags = List<String>.of(widget.selected);
  late final int _epoch;
  List<String> _suggestions = const [];
  String? _error;
  bool _loading = false;
  Timer? _timer;
  int _request = 0;
  bool get _current =>
      mounted &&
      widget.controller.available &&
      widget.controller.authorityVersion == _epoch;
  @override
  void initState() {
    super.initState();
    _epoch = widget.controller.authorityVersion;
    widget.controller.addListener(_authorityChanged);
  }

  void _authorityChanged() {
    if (!_current && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_authorityChanged);
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _timer?.cancel();
    final version = ++_request;
    setState(() {
      _error = null;
      _suggestions = const [];
      _loading = false;
    });
    if (value.trim().isEmpty) return;
    String prefix;
    try {
      prefix = PostTags.normalize(value);
    } on FormatException {
      return;
    }
    _timer = Timer(const Duration(milliseconds: 250), () async {
      if (!_current) return;
      setState(() => _loading = true);
      try {
        final words = await widget.controller.suggestPostTags(prefix);
        if (_current && version == _request) {
          setState(() => _suggestions = words);
        }
      } catch (_) {
        if (_current && version == _request) {
          setState(() => _error = '已有标签暂时无法加载，仍可添加新标签。');
        }
      } finally {
        if (_current && version == _request) setState(() => _loading = false);
      }
    });
  }

  bool _add(String raw) {
    try {
      final next = PostTags.normalizeAll([..._tags, raw]);
      setState(() {
        _tags
          ..clear()
          ..addAll(next);
        _error = null;
        _suggestions = const [];
        _loading = false;
      });
      ++_request;
      _timer?.cancel();
      _input.clear();
      return true;
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return false;
    }
  }

  void _done() {
    if (!_current) return;
    if (_input.text.trim().isNotEmpty && !_add(_input.text)) return;
    Navigator.pop(context, List<String>.unmodifiable(_tags));
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .6,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    hhText(context, '添加标签'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text('${_tags.length}/3'),
                TextButton(
                  onPressed: _done,
                  child: Text(hhText(context, '完成')),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _input,
              autofocus: true,
              onChanged: _changed,
              onSubmitted: _add,
              decoration: InputDecoration(
                prefixText: '#',
                hintText: hhText(context, '输入标签，最多10字'),
                suffixIcon: IconButton(
                  tooltip: hhText(context, '添加'),
                  onPressed: () => _add(_input.text),
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text('#$tag'),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                    ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                hhText(context, _error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              children: [
                if (_input.text.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: Text(hhText(context, '添加这个标签')),
                    subtitle: Text(_input.text),
                    onTap: () => _add(_input.text),
                  ),
                for (final tag in _suggestions)
                  ListTile(
                    title: Text('#$tag'),
                    trailing:
                        _tags.any((t) => t.toLowerCase() == tag.toLowerCase())
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _add(tag),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
