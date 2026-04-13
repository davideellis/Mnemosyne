import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownEditorPane extends StatefulWidget {
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
  State<MarkdownEditorPane> createState() => _MarkdownEditorPaneState();

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

class _MarkdownEditorPaneState extends State<MarkdownEditorPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      h1: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      h2: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      p: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      a: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Preview'),
            Tab(text: 'Edit'),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    return Markdown(
                      data: widget.controller.text.isEmpty
                          ? '_Nothing to preview yet._'
                          : MarkdownEditorPane.renderableMarkdownForPreview(
                              widget.controller.text,
                            ),
                      selectable: true,
                      padding: const EdgeInsets.all(16),
                      styleSheet: markdownStyle,
                      onTapLink: (text, href, title) {
                        if (href == null ||
                            !href.startsWith('mnemosyne://note/')) {
                          return;
                        }
                        final target = Uri.decodeComponent(
                          href.substring('mnemosyne://note/'.length),
                        );
                        widget.onOpenInternalLink(target);
                      },
                    );
                  },
                ),
              ),
              TextField(
                controller: widget.controller,
                readOnly: widget.isReadOnly,
                expands: true,
                maxLines: null,
                minLines: null,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write Markdown here...',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
