import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownEditorPane extends StatelessWidget {
  const MarkdownEditorPane({
    super.key,
    required this.controller,
    required this.isReadOnly,
    required this.onOpenInternalLink,
  });

  final TextEditingController controller;
  final bool isReadOnly;
  final ValueChanged<String> onOpenInternalLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Edit'),
              Tab(text: 'Preview'),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TabBarView(
              children: [
                TextField(
                  controller: controller,
                  readOnly: isReadOnly,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Write Markdown here...',
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      return Markdown(
                        data: controller.text.isEmpty
                            ? '_Nothing to preview yet._'
                            : renderableMarkdownForPreview(controller.text),
                        selectable: true,
                        padding: const EdgeInsets.all(16),
                        onTapLink: (text, href, title) {
                          if (href == null ||
                              !href.startsWith('mnemosyne://note/')) {
                            return;
                          }
                          final target = Uri.decodeComponent(
                            href.substring('mnemosyne://note/'.length),
                          );
                          onOpenInternalLink(target);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String renderableMarkdownForPreview(String markdown) {
    return markdown.replaceAllMapped(
      RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
      (match) {
        final target = match.group(1)?.trim() ?? '';
        if (target.isEmpty) {
          return match.group(0) ?? '';
        }
        final label = (match.group(2)?.trim().isNotEmpty ?? false)
            ? match.group(2)!.trim()
            : target;
        final encodedTarget = Uri.encodeComponent(target);
        return '[$label](mnemosyne://note/$encodedTarget)';
      },
    );
  }
}
