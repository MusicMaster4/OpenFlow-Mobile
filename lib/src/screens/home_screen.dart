import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/voxora_controller.dart';
import '../models/transcript_entry.dart';
import '../services/app_update_service.dart';
import '../services/openrouter_service.dart';
import '../theme.dart';
import 'statistics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final VoxoraController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _seenFeedbackSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seenFeedbackSerial = widget.controller.feedbackSerial;
    widget.controller.addListener(_handleFeedback);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleFeedback);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.refreshSystemIntegrations();
    }
  }

  void _handleFeedback() {
    final controller = widget.controller;
    if (controller.feedbackSerial == _seenFeedbackSerial ||
        controller.feedback == null) {
      return;
    }
    _seenFeedbackSerial = controller.feedbackSerial;
    final message = controller.feedback!;
    final isError = controller.feedbackIsError;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: isError ? VoxoraColors.danger : VoxoraColors.text,
                  size: 19,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(message)),
              ],
            ),
          ),
        );
    });
  }

  Future<void> _handleRecordTap() async {
    final controller = widget.controller;
    if (controller.isTranscribing) return;
    if (!controller.hasApiKey && !controller.isRecording) {
      await _openSettings();
      return;
    }
    if (controller.isRecording) {
      await controller.stopAndTranscribe();
    } else {
      await controller.startRecording();
    }
  }

  Future<void> _handleUpload() async {
    if (!widget.controller.hasApiKey) {
      await _openSettings();
      return;
    }
    await widget.controller.pickAndTranscribeAudio();
  }

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SettingsSheet(controller: widget.controller),
    );
  }

  Future<void> _openStatistics() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => StatisticsScreen(controller: widget.controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.controller,
        widget.controller.updates,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  onStatistics: _openStatistics,
                  onSettings: _openSettings,
                ),
                if (!controller.hasApiKey) _ApiKeyNotice(onTap: _openSettings),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fraction = controller.hasApiKey ? 0.43 : 0.37;
                      final recorderHeight = (constraints.maxHeight * fraction)
                          .clamp(230.0, 322.0);
                      return Column(
                        children: [
                          SizedBox(
                            height: recorderHeight,
                            child: _RecorderStage(
                              controller: controller,
                              onTap: _handleRecordTap,
                            ),
                          ),
                          Expanded(
                            child: _TranscriptPane(
                              controller: controller,
                              onUpload: _handleUpload,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onStatistics, required this.onSettings});

  final VoidCallback onStatistics;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/icon/openflow_icon.png',
              width: 42,
              height: 42,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OpenFlow',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.45,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Write at the speed of thought.',
                  style: TextStyle(color: VoxoraColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onStatistics,
            tooltip: 'Estatísticas',
            icon: const Icon(Icons.bar_chart_rounded, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: VoxoraColors.text,
              backgroundColor: VoxoraColors.surface,
              side: const BorderSide(color: VoxoraColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(width: 7),
          IconButton(
            onPressed: onSettings,
            tooltip: 'Configurações',
            icon: const Icon(Icons.tune_rounded, size: 20),
            style: IconButton.styleFrom(
              foregroundColor: VoxoraColors.text,
              backgroundColor: VoxoraColors.surface,
              side: const BorderSide(color: VoxoraColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiKeyNotice extends StatelessWidget {
  const _ApiKeyNotice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 2),
      child: Material(
        color: VoxoraColors.surfaceSoft,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: const Key('transcription-model-field'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: VoxoraColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.key_rounded,
                  color: VoxoraColors.mutedStrong,
                  size: 18,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Adicione sua chave da OpenRouter para começar',
                    style: TextStyle(
                      fontSize: 13,
                      color: VoxoraColors.mutedStrong,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: VoxoraColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecorderStage extends StatelessWidget {
  const _RecorderStage({required this.controller, required this.onTap});

  final VoxoraController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (controller.activity) {
      VoxoraActivity.idle => 'Toque para gravar',
      VoxoraActivity.recording => 'Toque para concluir',
      VoxoraActivity.transcribing => 'Transcrevendo',
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Text(
            controller.isRecording
                ? _formatDuration(controller.recordingDurationMs)
                : controller.isTranscribing
                ? controller.transcriptionModelLabel
                : 'PRONTO',
            key: ValueKey(controller.activity),
            style: TextStyle(
              color: controller.isRecording
                  ? VoxoraColors.accent
                  : controller.isTranscribing
                  ? VoxoraColors.mutedStrong
                  : VoxoraColors.muted,
              fontSize: controller.isRecording ? 14 : 11,
              fontWeight: FontWeight.w600,
              letterSpacing: controller.isRecording ? 0.8 : 1.25,
            ),
          ),
        ),
        const SizedBox(height: 5),
        _RadialRecorder(
          activity: controller.activity,
          amplitude: controller.amplitude,
          bands: controller.audioBands,
          onTap: onTap,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: VoxoraColors.mutedStrong,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (controller.isRecording)
          TextButton(
            onPressed: controller.cancelRecording,
            style: TextButton.styleFrom(
              foregroundColor: VoxoraColors.muted,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Cancelar'),
          )
        else
          const SizedBox(height: 36),
      ],
    );
  }
}

class _RadialRecorder extends StatefulWidget {
  const _RadialRecorder({
    required this.activity,
    required this.amplitude,
    required this.bands,
    required this.onTap,
  });

  final VoxoraActivity activity;
  final double amplitude;
  final List<double> bands;
  final VoidCallback onTap;

  @override
  State<_RadialRecorder> createState() => _RadialRecorderState();
}

class _RadialRecorderState extends State<_RadialRecorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  final List<double> _currentBands = List<double>.filled(11, 0);
  double _currentLevel = 0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1500),
          )
          ..addListener(_tick)
          ..repeat();
  }

  void _tick() {
    final recording = widget.activity == VoxoraActivity.recording;
    final targetLevel = recording ? widget.amplitude : 0.0;
    _currentLevel += (targetLevel - _currentLevel) * 0.34;
    for (var index = 0; index < _currentBands.length; index++) {
      final target = recording && index < widget.bands.length
          ? widget.bands[index]
          : 0.0;
      _currentBands[index] += (target - _currentBands[index]) * 0.40;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.activity == VoxoraActivity.transcribing;
    final recording = widget.activity == VoxoraActivity.recording;
    final color = switch (widget.activity) {
      VoxoraActivity.idle => VoxoraColors.text,
      VoxoraActivity.recording => VoxoraColors.ink,
      VoxoraActivity.transcribing => VoxoraColors.surfaceRaised,
    };
    final icon = switch (widget.activity) {
      VoxoraActivity.idle => Icons.mic_none_rounded,
      VoxoraActivity.recording => Icons.stop_rounded,
      VoxoraActivity.transcribing => Icons.graphic_eq_rounded,
    };
    final iconColor = switch (widget.activity) {
      VoxoraActivity.idle => VoxoraColors.ink,
      VoxoraActivity.recording => VoxoraColors.text,
      VoxoraActivity.transcribing => VoxoraColors.mutedStrong,
    };
    final pulse = (math.sin(_ticker.value * math.pi * 2) + 1) / 2;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.activity == VoxoraActivity.recording
          ? 'Finalizar gravação e transcrever'
          : 'Iniciar gravação',
      child: GestureDetector(
        onTap: disabled ? null : widget.onTap,
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: disabled ? null : () => setState(() => _pressed = false),
        child: SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size.square(180),
                painter: _SpectrumRingPainter(
                  progress: _ticker.value,
                  activity: widget.activity,
                  level: _currentLevel,
                  bands: _currentBands,
                ),
              ),
              AnimatedScale(
                scale: _pressed ? 0.93 : 1,
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: switch (widget.activity) {
                      VoxoraActivity.recording => Border.all(
                        color: VoxoraColors.accent.withValues(
                          alpha: 0.55 + pulse * 0.45,
                        ),
                        width: 1.6,
                      ),
                      VoxoraActivity.transcribing => Border.all(
                        color: VoxoraColors.borderStrong,
                      ),
                      VoxoraActivity.idle => null,
                    },
                    boxShadow: [
                      BoxShadow(
                        color: recording
                            ? VoxoraColors.accent.withValues(
                                alpha: 0.14 + pulse * 0.10,
                              )
                            : Colors.black.withValues(alpha: 0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: iconColor, size: 36),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpectrumRingPainter extends CustomPainter {
  const _SpectrumRingPainter({
    required this.progress,
    required this.activity,
    required this.level,
    required this.bands,
  });

  final double progress;
  final VoxoraActivity activity;
  final double level;
  final List<double> bands;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = VoxoraColors.border;
    canvas.drawCircle(center, 65, baseRing);

    if (activity == VoxoraActivity.idle) {
      canvas.drawCircle(
        center,
        73,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = VoxoraColors.border.withValues(alpha: 0.45),
      );
      return;
    }

    if (activity == VoxoraActivity.transcribing) {
      final paint = Paint()
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = VoxoraColors.text;
      for (var index = 0; index < 20; index++) {
        final angle = progress * math.pi * 2 + index * math.pi * 2 / 20;
        final alpha = ((index + 1) / 20).clamp(0.15, 1.0);
        paint.color = VoxoraColors.text.withValues(alpha: alpha * 0.82);
        final start = center + Offset(math.cos(angle), math.sin(angle)) * 69;
        final end = center + Offset(math.cos(angle), math.sin(angle)) * 76;
        canvas.drawLine(start, end, paint);
      }
      return;
    }

    final paint = Paint()
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = VoxoraColors.text;
    const barCount = 22;
    for (var index = 0; index < barCount; index++) {
      final mirrored = index < 11 ? index : 21 - index;
      final frequency = mirrored < bands.length ? bands[mirrored] : 0.0;
      final intensity = math.min(1.0, frequency * 1.12 + level * 0.16);
      final angle = -math.pi / 2 + index * math.pi * 2 / barCount;
      final inner = 69.0;
      final outer = inner + 5 + intensity * 17;
      final direction = Offset(math.cos(angle), math.sin(angle));
      paint.color = VoxoraColors.text.withValues(
        alpha: 0.28 + intensity * 0.72,
      );
      canvas.drawLine(
        center + direction * inner,
        center + direction * outer,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumRingPainter oldDelegate) => true;
}

class _TranscriptPane extends StatelessWidget {
  const _TranscriptPane({required this.controller, required this.onUpload});

  final VoxoraController controller;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: VoxoraColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: VoxoraColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 9),
          Container(
            width: 34,
            height: 4,
            decoration: BoxDecoration(
              color: VoxoraColors.borderStrong,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'Transcrições',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: VoxoraColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: VoxoraColors.border),
                        ),
                        child: Text(
                          '${controller.history.length}/100',
                          style: const TextStyle(
                            color: VoxoraColors.muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: controller.isBusy ? null : onUpload,
                  tooltip: 'Enviar arquivo de áudio',
                  icon: const Icon(Icons.audio_file_outlined, size: 20),
                  style: IconButton.styleFrom(
                    foregroundColor: VoxoraColors.text,
                    backgroundColor: VoxoraColors.surfaceRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: VoxoraColors.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: controller.history.isEmpty
                ? const _EmptyTranscripts()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
                    physics: const BouncingScrollPhysics(),
                    itemCount: controller.history.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = controller.history[index];
                      return _TranscriptCard(
                        entry: entry,
                        onCopy: () => controller.copyText(entry.text),
                        onDelete: () => controller.deleteEntry(entry.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTranscripts extends StatelessWidget {
  const _EmptyTranscripts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notes_rounded,
              color: VoxoraColors.borderStrong,
              size: 30,
            ),
            SizedBox(height: 10),
            Text(
              'Suas transcrições aparecem aqui',
              style: TextStyle(color: VoxoraColors.mutedStrong, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({
    required this.entry,
    required this.onCopy,
    required this.onDelete,
  });

  final TranscriptEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: VoxoraColors.surfaceSoft,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onCopy,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VoxoraColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  entry.text,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: VoxoraColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_sourceLabel(entry.source)}  •  ${_relativeTime(entry.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VoxoraColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Custo desta transcrição na OpenRouter',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VoxoraColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: VoxoraColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.payments_outlined,
                            size: 12,
                            color: VoxoraColors.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatCostUsd(entry.costUsd),
                            style: const TextStyle(
                              color: VoxoraColors.mutedStrong,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    onPressed: onCopy,
                    tooltip: 'Copiar',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    color: VoxoraColors.toggle,
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    color: VoxoraColors.surfaceRaised,
                    iconSize: 18,
                    iconColor: VoxoraColors.muted,
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                              color: VoxoraColors.danger,
                            ),
                            SizedBox(width: 9),
                            Text('Excluir'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller});

  final VoxoraController controller;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _apiKeyController;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _openModelPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _TranscriptionModelPicker(controller: widget.controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedBuilder(
      // Update checks and downloads run independently from the main
      // controller. Listen to both so the open settings sheet reflects each
      // update phase immediately, without requiring it to be closed/reopened.
      animation: Listenable.merge([
        widget.controller,
        widget.controller.updates,
      ]),
      builder: (context, _) {
        final controller = widget.controller;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: VoxoraColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: VoxoraColors.border)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Configurações',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  key: const Key('settings-list'),
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
                  children: [
                    const _SettingsLabel('OPENROUTER'),
                    const SizedBox(height: 8),
                    _SettingsPanel(
                      child: Column(
                        children: [
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              hintText: controller.hasApiKey
                                  ? 'Chave configurada ••••••••'
                                  : 'sk-or-v1-…',
                              prefixIcon: const Icon(
                                Icons.key_rounded,
                                size: 19,
                              ),
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscureKey = !_obscureKey),
                                icon: Icon(
                                  _obscureKey
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 19,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    final saved = await controller.saveApiKey(
                                      _apiKeyController.text,
                                    );
                                    if (saved) _apiKeyController.clear();
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: VoxoraColors.text,
                                    foregroundColor: const Color(0xFF111110),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                  child: const Text('Salvar chave'),
                                ),
                              ),
                              if (controller.hasApiKey) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: controller.deleteApiKey,
                                  tooltip: 'Remover chave',
                                  color: VoxoraColors.danger,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TranscriptionModelField(
                      controller: controller,
                      onTap: controller.isBusy ? null : _openModelPicker,
                    ),
                    const SizedBox(height: 22),
                    const _SettingsLabel('CÍRCULO FLUTUANTE'),
                    const SizedBox(height: 8),
                    _SettingsPanel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsSwitch(
                            icon: Icons.bubble_chart_outlined,
                            title: 'Mostrar sobre outros apps',
                            subtitle: controller.overlayPermissionGranted
                                ? 'Um toque grava; outro finaliza'
                                : 'Requer permissão do Android',
                            value: controller.floatingOverlayEnabled,
                            onChanged: controller.setFloatingOverlayEnabled,
                          ),
                          const Divider(height: 1, indent: 56),
                          _SettingsSwitch(
                            icon: Icons.keyboard_alt_outlined,
                            title: 'Colar no campo selecionado',
                            subtitle: controller.accessibilityEnabled
                                ? 'Acessibilidade ativa'
                                : 'Opcional • requer Acessibilidade',
                            value: controller.autoPaste,
                            onChanged: controller.setAutoPaste,
                          ),
                          if (controller.autoPaste &&
                              !controller.accessibilityEnabled)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: VoxoraColors.accent.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: VoxoraColors.accent.withValues(
                                      alpha: 0.32,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Libere a configuração restrita',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    const Text(
                                      '1. Nos detalhes do app, abra o menu ⋮ e toque em “Permitir configurações restritas”.\n2. Volte e ative “OpenFlow — colar transcrição” em Acessibilidade.',
                                      style: TextStyle(
                                        color: VoxoraColors.mutedStrong,
                                        fontSize: 11.5,
                                        height: 1.4,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: controller
                                                .openAppDetailsSettings,
                                            child: const Text('1. Liberar'),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FilledButton.tonal(
                                            onPressed: controller
                                                .openAccessibilitySettings,
                                            child: const Text('2. Ativar'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                            child: Text(
                              'Arraste para mover. Segure quando estiver ocioso para remover até a próxima abertura do app. Durante a gravação, toque duas vezes para cancelar. O OpenFlow não lê nem armazena o conteúdo da tela.',
                              style: TextStyle(
                                color: VoxoraColors.muted,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SettingsLabel('ÁUDIO E RESPOSTA'),
                    const SizedBox(height: 8),
                    _SettingsPanel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsSwitch(
                            icon: Icons.volume_up_outlined,
                            title: 'Sons e vibração',
                            subtitle:
                                'Ao iniciar, concluir, cancelar e finalizar',
                            value: controller.soundEffectsEnabled,
                            onChanged: controller.setSoundEffectsEnabled,
                          ),
                          const Divider(height: 1, indent: 56),
                          _SettingsSwitch(
                            icon: Icons.notifications_off_outlined,
                            title: 'Silenciar durante a gravação',
                            subtitle: controller.notificationPolicyAccessGranted
                                ? 'Silêncio total autorizado'
                                : 'Ativado • autorize para incluir notificações',
                            value: controller.silenceWhileRecording,
                            onChanged: controller.setSilenceWhileRecording,
                          ),
                          if (controller.silenceWhileRecording &&
                              !controller.notificationPolicyAccessGranted)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Sem este acesso, a mídia é pausada ou silenciada; notificações dependem do Android.',
                                      style: TextStyle(
                                        color: VoxoraColors.muted,
                                        fontSize: 11,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  TextButton(
                                    onPressed: controller
                                        .openNotificationPolicySettings,
                                    child: const Text('Autorizar'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SettingsLabel('SAÍDA'),
                    const SizedBox(height: 8),
                    _SettingsPanel(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _SettingsSwitch(
                            icon: Icons.copy_all_outlined,
                            title: 'Copiar automaticamente',
                            subtitle:
                                'Mantém a transcrição na área de transferência',
                            value: controller.autoCopy,
                            onChanged: controller.setAutoCopy,
                          ),
                          const Divider(height: 1, indent: 56),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.language_rounded,
                                  color: VoxoraColors.muted,
                                  size: 21,
                                ),
                                const SizedBox(width: 18),
                                const Expanded(
                                  child: Text(
                                    'Idioma do áudio',
                                    style: TextStyle(fontSize: 14),
                                  ),
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: controller.languageHint,
                                    dropdownColor: VoxoraColors.surfaceRaised,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'auto',
                                        child: Text('Automático'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'pt',
                                        child: Text('Português'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'en',
                                        child: Text('Inglês'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'es',
                                        child: Text('Espanhol'),
                                      ),
                                    ],
                                    onChanged: controller.isBusy
                                        ? null
                                        : (value) {
                                            if (value != null) {
                                              controller.setLanguageHint(value);
                                            }
                                          },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const _SettingsLabel('SOBRE E ATUALIZAÇÕES'),
                    const SizedBox(height: 8),
                    _AboutAndUpdates(
                      updates: controller.updates,
                      transcriptionModel: controller.transcriptionModel,
                    ),
                    if (controller.history.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      const _SettingsLabel('DADOS LOCAIS'),
                      const SizedBox(height: 8),
                      _SettingsPanel(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${controller.history.length} transcrições neste aparelho',
                                style: const TextStyle(
                                  color: VoxoraColors.mutedStrong,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: controller.clearHistory,
                              style: TextButton.styleFrom(
                                foregroundColor: VoxoraColors.danger,
                              ),
                              child: const Text('Limpar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TranscriptionModelField extends StatelessWidget {
  const _TranscriptionModelField({
    required this.controller,
    required this.onTap,
  });

  final VoxoraController controller;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final selected = controller.transcriptionModels
        .where((model) => model.id == controller.transcriptionModel)
        .firstOrNull;
    return Semantics(
      button: true,
      label: 'Modelo de transcrição',
      value: selected?.name ?? controller.transcriptionModel,
      child: Material(
        color: VoxoraColors.surfaceSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: VoxoraColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.model_training_outlined,
                  color: VoxoraColors.muted,
                  size: 21,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Modelo de transcrição',
                        style: TextStyle(
                          color: VoxoraColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        selected?.name ?? controller.transcriptionModel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (selected != null && selected.id != selected.name) ...[
                        const SizedBox(height: 2),
                        Text(
                          selected.id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VoxoraColors.muted,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.unfold_more_rounded,
                  color: VoxoraColors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptionModelPicker extends StatefulWidget {
  const _TranscriptionModelPicker({required this.controller});

  final VoxoraController controller;

  @override
  State<_TranscriptionModelPicker> createState() =>
      _TranscriptionModelPickerState();
}

class _TranscriptionModelPickerState extends State<_TranscriptionModelPicker> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.controller.loadTranscriptionModels());
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final normalizedQuery = _query.trim().toLowerCase();
        final models = controller.transcriptionModels
            .where((model) {
              if (normalizedQuery.isEmpty) return true;
              return model.name.toLowerCase().contains(normalizedQuery) ||
                  model.id.toLowerCase().contains(normalizedQuery) ||
                  model.description.toLowerCase().contains(normalizedQuery);
            })
            .toList(growable: false);
        final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

        return Container(
          height: MediaQuery.sizeOf(context).height * 0.82,
          padding: EdgeInsets.only(bottom: keyboardInset),
          decoration: const BoxDecoration(
            color: VoxoraColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: VoxoraColors.border)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 10, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Modelo de transcrição',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Modelos disponíveis na OpenRouter',
                            style: TextStyle(
                              color: VoxoraColors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  key: const Key('transcription-model-search'),
                  controller: _searchController,
                  autofocus: true,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Pesquisar por nome ou provedor',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar pesquisa',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _modelList(context, controller, models)),
            ],
          ),
        );
      },
    );
  }

  Widget _modelList(
    BuildContext context,
    VoxoraController controller,
    List<TranscriptionModel> models,
  ) {
    if (controller.isLoadingTranscriptionModels && models.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 14),
            Text(
              'Carregando modelos…',
              style: TextStyle(color: VoxoraColors.mutedStrong),
            ),
          ],
        ),
      );
    }

    if (controller.transcriptionModelsError != null && models.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                color: VoxoraColors.muted,
                size: 30,
              ),
              const SizedBox(height: 12),
              Text(
                controller.transcriptionModelsError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: VoxoraColors.mutedStrong),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () =>
                    controller.loadTranscriptionModels(force: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    if (models.isEmpty) {
      return const Center(
        child: Text(
          'Nenhum modelo encontrado.',
          style: TextStyle(color: VoxoraColors.mutedStrong),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => controller.loadTranscriptionModels(force: true),
      child: ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 24),
        itemCount: models.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 54),
        itemBuilder: (context, index) {
          final model = models[index];
          final selected = model.id == controller.transcriptionModel;
          return ListTile(
            selected: selected,
            selectedTileColor: VoxoraColors.text.withValues(alpha: 0.07),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? VoxoraColors.text : VoxoraColors.muted,
              size: 21,
            ),
            title: Text(
              model.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              model.id,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: VoxoraColors.muted, fontSize: 11),
            ),
            onTap: () async {
              await controller.setTranscriptionModel(model.id);
              if (context.mounted) Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}

class _AboutAndUpdates extends StatelessWidget {
  const _AboutAndUpdates({
    required this.updates,
    required this.transcriptionModel,
  });

  final AppUpdateService updates;
  final String transcriptionModel;

  @override
  Widget build(BuildContext context) {
    final build = updates.build;
    final percent = updates.progress == null
        ? null
        : (updates.progress! * 100).round();
    final status = switch (updates.phase) {
      AppUpdatePhase.idle =>
        'Seu histórico, preferências e chave permanecem salvos nas atualizações oficiais.',
      AppUpdatePhase.checking => 'Consultando o canal ${build.channelLabel}…',
      AppUpdatePhase.current =>
        'Você já está na versão mais recente do canal ${build.channelLabel}.',
      AppUpdatePhase.available =>
        'OpenFlow ${updates.available!.versionName} está disponível para este canal.',
      AppUpdatePhase.downloading =>
        percent == null
            ? 'Baixando e verificando o APK…'
            : 'Baixando e verificando o APK… $percent%',
      AppUpdatePhase.awaitingPermission =>
        'Autorize esta fonte no Android, volte ao OpenFlow e continue a instalação.',
      AppUpdatePhase.readyToInstall =>
        'O APK está verificado e pronto. Toque para abrir o instalador do Android.',
      AppUpdatePhase.installing =>
        'O instalador do Android foi aberto. Confirme para concluir.',
      AppUpdatePhase.failed =>
        updates.errorMessage ?? 'Não foi possível verificar atualizações.',
    };

    final (label, icon, action) = switch (updates.phase) {
      AppUpdatePhase.available => (
        'Baixar e instalar',
        Icons.system_update_alt_rounded,
        updates.downloadAndInstall,
      ),
      AppUpdatePhase.awaitingPermission => (
        'Continuar instalação',
        Icons.install_mobile_rounded,
        updates.continueInstallation,
      ),
      AppUpdatePhase.readyToInstall => (
        'Abrir instalador',
        Icons.install_mobile_rounded,
        updates.continueInstallation,
      ),
      AppUpdatePhase.checking ||
      AppUpdatePhase.downloading ||
      AppUpdatePhase.installing => (
        updates.phase == AppUpdatePhase.checking
            ? 'Verificando…'
            : updates.phase == AppUpdatePhase.downloading
            ? 'Baixando…'
            : 'Instalando…',
        Icons.downloading_rounded,
        null,
      ),
      _ => (
        updates.phase == AppUpdatePhase.current
            ? 'Verificar novamente'
            : 'Verificar atualizações',
        Icons.refresh_rounded,
        updates.isSupported ? updates.check : null,
      ),
    };

    return _SettingsPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    'assets/icon/openflow_icon.png',
                    width: 44,
                    height: 44,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OpenFlow Mobile',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'v${build.versionName}  •  $transcriptionModel',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: VoxoraColors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _ChannelPill(label: build.channelLabel),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  build.channel == 'testing'
                      ? 'Este APK recebe somente versões beta da branch testing. Releases stable nunca são oferecidos aqui.'
                      : 'Este APK recebe somente versões stable da branch main. Releases beta nunca são oferecidos aqui.',
                  style: const TextStyle(
                    color: VoxoraColors.mutedStrong,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    status,
                    key: ValueKey(updates.phase),
                    style: TextStyle(
                      color: updates.phase == AppUpdatePhase.failed
                          ? VoxoraColors.danger
                          : VoxoraColors.muted,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
                if (updates.phase == AppUpdatePhase.downloading) ...[
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: updates.progress,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(99),
                    backgroundColor: VoxoraColors.border,
                    color: VoxoraColors.text,
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: action,
                  icon: updates.isBusy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(icon, size: 18),
                  label: Text(label),
                  style: FilledButton.styleFrom(
                    backgroundColor: VoxoraColors.text,
                    foregroundColor: const Color(0xFF111110),
                    disabledBackgroundColor: VoxoraColors.surfaceRaised,
                    disabledForegroundColor: VoxoraColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelPill extends StatelessWidget {
  const _ChannelPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final beta = label == 'beta';
    final color = beta ? VoxoraColors.accent : VoxoraColors.mutedStrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.65,
        ),
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: VoxoraColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VoxoraColors.border),
      ),
      child: child,
    );
  }
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: VoxoraColors.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.15,
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: VoxoraColors.muted, size: 21),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: VoxoraColors.muted, fontSize: 11.5),
      ),
      activeThumbColor: VoxoraColors.toggle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

String _formatDuration(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String _formatCostUsd(double value) {
  final normalized = value.isFinite && value > 0 ? value : 0.0;
  final decimals = normalized > 0 && normalized < 0.0001 ? 6 : 4;
  return '\$${normalized.toStringAsFixed(decimals)}';
}

String _sourceLabel(String source) {
  if (source.toLowerCase().contains('grava')) return 'Gravação';
  return source.length > 22 ? '${source.substring(0, 20)}…' : source;
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'agora';
  if (difference.inHours < 1) return '${difference.inMinutes} min';
  if (difference.inDays < 1) return '${difference.inHours} h';
  if (difference.inDays < 7) return '${difference.inDays} d';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}
