import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app/settings.dart';
import '../magic/claude_dream.dart';
import '../magic/recommender.dart';
import 'brand.dart';
import 'canvas_layers.dart';

/// "What do you imagine?" — type an idea, get light-art recommendations,
/// pick one to have it built in the air.
class ImagineSheet extends StatefulWidget {
  const ImagineSheet({super.key, required this.settings, required this.recommender});

  final AppSettings settings;
  final Recommender recommender;

  static Future<Recommendation?> show(BuildContext context, AppSettings settings, Recommender recommender) {
    return showModalBottomSheet<Recommendation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ImagineSheet(settings: settings, recommender: recommender),
    );
  }

  @override
  State<ImagineSheet> createState() => _ImagineSheetState();
}

class _ImagineSheetState extends State<ImagineSheet> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<Recommendation> _recs = const [];
  Recommendation? _dreamed;
  bool _dreaming = false;
  String? _dreamError;

  static const _ideas = [
    'moon over the mountains',
    'galaxy of love',
    'birthday balloons',
    'ocean at sunset',
    'royal crown',
    'rocket to the stars',
    'cherry blossom spring',
    'winter snowflakes',
  ];

  @override
  void initState() {
    super.initState();
    _recs = widget.recommender.fromImagination('');
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      setState(() {
        _recs = widget.recommender.fromImagination(_text.text);
        _dreamed = null;
        _dreamError = null;
      });
    });
  }

  Future<void> _dream() async {
    final idea = _text.text.trim();
    if (idea.isEmpty) {
      setState(() => _dreamError = 'Describe your idea first.');
      return;
    }
    setState(() {
      _dreaming = true;
      _dreamError = null;
    });
    try {
      final art = await ClaudeDreamer(
        apiKey: widget.settings.claudeApiKey!,
        model: widget.settings.claudeModel,
      ).dream(idea);
      if (!mounted) return;
      setState(() {
        _dreamed = Recommendation(
          art: art,
          reason: 'Dreamed up by Claude from your words',
          score: 10,
          source: RecommendationSource.ai,
        );
      });
    } on DreamException catch (e) {
      if (mounted) setState(() => _dreamError = e.message);
    } finally {
      if (mounted) setState(() => _dreaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final recs = [?_dreamed, ..._recs];
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.86),
        decoration: BoxDecoration(
          color: Brand.night.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Brand.violet.withValues(alpha: 0.35)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Brand.orchid),
                    const SizedBox(width: 10),
                    Text('What do you imagine?',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Brand.ink, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: TextField(
                  controller: _text,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => widget.settings.hasClaudeKey ? _dream() : null,
                  style: const TextStyle(color: Brand.ink),
                  decoration: InputDecoration(
                    hintText: 'e.g. a glowing moon over the mountains',
                    hintStyle: TextStyle(color: Brand.mist.withValues(alpha: 0.6)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    prefixIcon: const Icon(Icons.lightbulb_outline, color: Brand.mist),
                    suffixIcon: _text.text.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.close, color: Brand.mist), onPressed: _text.clear),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    for (final idea in _ideas)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(idea),
                          labelStyle: const TextStyle(color: Brand.ink, fontSize: 12),
                          backgroundColor: Brand.deep,
                          side: BorderSide(color: Brand.violet.withValues(alpha: 0.4)),
                          onPressed: () {
                            _text.text = idea;
                            _text.selection = TextSelection.collapsed(offset: idea.length);
                          },
                        ),
                      ),
                  ],
                ),
              ),
              _DreamBanner(
                hasKey: widget.settings.hasClaudeKey,
                dreaming: _dreaming,
                error: _dreamError,
                onDream: _dream,
              ),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: recs.length,
                  itemBuilder: (context, i) => _RecommendationCard(
                    rec: recs[i],
                    onTap: () => Navigator.of(context).pop(recs[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DreamBanner extends StatelessWidget {
  const _DreamBanner({required this.hasKey, required this.dreaming, required this.error, required this.onDream});
  final bool hasKey;
  final bool dreaming;
  final String? error;
  final VoidCallback onDream;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasKey)
            DecoratedBox(
              decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(16)),
              child: TextButton.icon(
                onPressed: dreaming ? null : onDream,
                icon: dreaming
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.auto_fix_high, color: Colors.white),
                label: Text(
                  dreaming ? 'Dreaming it up…' : 'Dream anything with Claude',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            Text(
              'Tip: add a Claude API key in Settings to dream up any idea, beyond the built-in library.',
              style: TextStyle(color: Brand.mist.withValues(alpha: 0.7), fontSize: 12),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error!, style: const TextStyle(color: Color(0xFFFF8FA3), fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.rec, required this.onTap});
  final Recommendation rec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = rec.art.palette.colors.first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF15103A), Color(0xFF07061A)],
            ),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: CustomPaint(painter: ArtPreviewPainter(rec.art))),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (rec.source == RecommendationSource.ai)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.auto_fix_high, size: 14, color: Brand.orchid),
                          ),
                        Expanded(
                          child: Text(
                            rec.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rec.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Brand.mist.withValues(alpha: 0.75), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
