import 'package:material_ui/material_ui.dart';

import '../app/settings.dart';
import '../paint/brush.dart';
import 'about_screen.dart';
import 'brand.dart';

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.settings});
  final AppSettings settings;

  static Future<void> show(BuildContext context, AppSettings settings) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SettingsSheet(settings: settings),
      );

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late final TextEditingController _key = TextEditingController(text: widget.settings.claudeApiKey ?? '');
  bool _showKey = false;

  static const _models = {
    'claude-opus-5-5': 'Claude Opus 5.5 (best drawings)',
    'claude-sonnet-5-5': 'Claude Sonnet 5.5 (balanced)',
    'claude-haiku-5-5': 'Claude Haiku 5.5 (fastest)',
  };

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          decoration: BoxDecoration(
            color: Brand.night.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Brand.violet.withValues(alpha: 0.35)),
          ),
          child: SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text('Settings', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Brand.ink, fontWeight: FontWeight.w600)),
                const _Section('Air brush'),
                Text('Paint gesture', style: _label),
                const SizedBox(height: 6),
                SegmentedButton<DrawGesture>(
                  segments: [for (final g in DrawGesture.values) ButtonSegment(value: g, label: Text(g.label))],
                  selected: {s.drawGesture},
                  onSelectionChanged: (v) => s.update((x) => x.drawGesture = v.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.drawGesture.help, style: _help),
                ),
                _slider('Steadiness', s.smoothing, 0, 1, (v) => s.update((x) => x.smoothing = v),
                    help: 'Higher smooths shaky hands; lower follows fast motion more tightly.'),
                _switch('Depth-sensitive width', s.depthWidth, (v) => s.update((x) => x.depthWidth = v),
                    help: 'Bring your hand closer to paint thicker light.'),
                _switch('Open palm to undo', s.palmUndo, (v) => s.update((x) => x.palmUndo = v),
                    help: 'Hold an open palm for about a second to undo the last stroke.'),
                _switch('Suggest art from sketches', s.sketchSuggestions, (v) => s.update((x) => x.sketchSuggestions = v),
                    help: 'Draw a circle, triangle, wave or spiral and Aerograph offers to transform it.'),
                _switch('Show hand skeleton', s.showSkeleton, (v) => s.update((x) => x.showSkeleton = v)),
                const _Section('Light'),
                Text('Light mode', style: _label),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in LightMode.values)
                      ChoiceChip(
                        label: Text(m.label),
                        selected: s.lightMode == m,
                        onSelected: (_) => s.update((x) => x.lightMode = m),
                      ),
                  ],
                ),
                _slider('Camera dim', s.cameraDim, 0, 0.9, (v) => s.update((x) => x.cameraDim = v),
                    help: 'Darken the camera so your light pops.'),
                const _Section('Camera'),
                Text('Mirror tracking', style: _label),
                const SizedBox(height: 6),
                SegmentedButton<MirrorMode>(
                  segments: const [
                    ButtonSegment(value: MirrorMode.auto, label: Text('Auto')),
                    ButtonSegment(value: MirrorMode.on, label: Text('On')),
                    ButtonSegment(value: MirrorMode.off, label: Text('Off')),
                  ],
                  selected: {s.mirror},
                  onSelectionChanged: (v) => s.update((x) => x.mirror = v.first),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('If the brush moves opposite to your finger, switch this.', style: _help),
                ),
                const _Section('Imagination (optional)'),
                Text(
                  'The built-in library works offline. Add your own Anthropic API key to let Claude dream up '
                  'any idea you type. The key is stored only in this device\'s secure keychain/keystore and is '
                  'sent only to api.anthropic.com.',
                  style: _help,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _key,
                  obscureText: !_showKey,
                  style: const TextStyle(color: Brand.ink),
                  decoration: InputDecoration(
                    labelText: 'Claude API key',
                    hintText: 'sk-ant-…',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                  onSubmitted: s.setClaudeApiKey,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () async {
                        await s.setClaudeApiKey(_key.text);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.hasClaudeKey ? 'Claude key saved' : 'Claude key removed')),
                          );
                        }
                      },
                      child: const Text('Save key'),
                    ),
                    const SizedBox(width: 8),
                    if (s.hasClaudeKey)
                      TextButton(
                        onPressed: () async {
                          _key.clear();
                          await s.setClaudeApiKey(null);
                        },
                        child: const Text('Remove'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _models.containsKey(s.claudeModel) ? s.claudeModel : _models.keys.first,
                  dropdownColor: Brand.deep,
                  decoration: InputDecoration(
                    labelText: 'Model',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  items: [
                    for (final e in _models.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => s.update((x) => x.claudeModel = v ?? x.claudeModel),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline, color: Brand.mist),
                  title: const Text('About Aerograph', style: TextStyle(color: Brand.ink)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
                ),
                const SizedBox(height: 8),
                const Center(child: AuthorCredit(compact: true)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _label => const TextStyle(color: Brand.ink, fontWeight: FontWeight.w500);
  TextStyle get _help => TextStyle(color: Brand.mist.withValues(alpha: 0.7), fontSize: 12);

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String? help}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _label),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
          if (help != null) Text(help, style: _help),
        ],
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged, {String? help}) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: _label),
      subtitle: help == null ? null : Text(help, style: _help),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(color: Brand.orchid, fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w600),
        ),
      );
}
