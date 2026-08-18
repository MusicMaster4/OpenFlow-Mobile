import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/voxora_controller.dart';
import '../models/usage_stats.dart';
import '../theme.dart';

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.controller});

  final VoxoraController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final stats = controller.usageStats;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: VoxoraColors.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('Estatísticas'),
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
              children: [
                const Text(
                  'Seu ritmo no OpenFlow',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'As métricas são calculadas e guardadas somente neste aparelho.',
                  style: TextStyle(
                    color: VoxoraColors.mutedStrong,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.45,
                  children: [
                    _MetricCard(
                      label: 'SEQUÊNCIA',
                      value: '${stats.streakDays}',
                      suffix: stats.streakDays == 1 ? 'dia' : 'dias',
                      icon: Icons.local_fire_department_outlined,
                      color: VoxoraColors.warning,
                    ),
                    _MetricCard(
                      label: 'DIAS DE USO',
                      value: '${stats.totalDays}',
                      suffix: stats.totalDays == 1 ? 'dia' : 'dias',
                      icon: Icons.calendar_today_outlined,
                      color: VoxoraColors.text,
                    ),
                    _MetricCard(
                      label: 'PALAVRAS',
                      value: _compactNumber(stats.totalWords),
                      suffix: 'faladas',
                      icon: Icons.notes_rounded,
                      color: VoxoraColors.accent,
                    ),
                    _MetricCard(
                      label: 'VELOCIDADE',
                      value: stats.averageWpm.round().toString(),
                      suffix: 'PPM média',
                      icon: Icons.speed_rounded,
                      color: VoxoraColors.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const _SectionLabel('ÚLTIMOS 7 DIAS'),
                const SizedBox(height: 8),
                _WeeklyChart(stats: stats),
                const SizedBox(height: 22),
                const _SectionLabel('VISÃO GERAL'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: VoxoraColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: VoxoraColors.border),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.mic_none_rounded,
                        label: 'Transcrições concluídas',
                        value: '${stats.totalTranscriptions}',
                      ),
                      const Divider(height: 1, indent: 54),
                      _DetailRow(
                        icon: Icons.schedule_rounded,
                        label: 'Tempo falando',
                        value: _formatDuration(stats.totalAudioMs),
                      ),
                      const Divider(height: 1, indent: 54),
                      _DetailRow(
                        icon: Icons.bolt_rounded,
                        label: 'Tempo estimado poupado',
                        value: _formatDuration(stats.estimatedTimeSavedMs),
                      ),
                      const Divider(height: 1, indent: 54),
                      _DetailRow(
                        icon: Icons.timer_outlined,
                        label: 'Processamento médio',
                        value: stats.totalTranscriptions == 0
                            ? '—'
                            : '${(stats.averageTranscriptionMs / 1000).toStringAsFixed(1)} s',
                      ),
                      const Divider(height: 1, indent: 54),
                      _DetailRow(
                        icon: Icons.payments_outlined,
                        label: 'Custo total estimado',
                        value: '\$${stats.totalCostUsd.toStringAsFixed(4)}',
                      ),
                    ],
                  ),
                ),
                if (stats.totalTranscriptions > 0) ...[
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Zerar estatísticas?'),
                          content: const Text(
                            'O histórico de transcrições será mantido, mas as métricas acumuladas começarão do zero.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancelar'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: TextButton.styleFrom(
                                foregroundColor: VoxoraColors.danger,
                              ),
                              child: const Text('Zerar'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await controller.resetUsageStats();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: VoxoraColors.muted,
                    ),
                    child: const Text('Zerar estatísticas'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String suffix;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VoxoraColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoxoraColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: VoxoraColors.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.9,
                  ),
                ),
              ),
              Icon(icon, size: 17, color: color),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w600,
              height: 1,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            suffix,
            style: const TextStyle(
              color: VoxoraColors.mutedStrong,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({required this.stats});

  final UsageStats stats;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = List.generate(7, (index) {
      final day = DateTime(today.year, today.month, today.day - (6 - index));
      final key = UsageStats.dayKey(day);
      return (date: day, words: stats.dailyWords[key] ?? 0);
    });
    final maxWords = days.fold<int>(
      0,
      (value, day) => math.max(value, day.words),
    );
    const labels = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

    return Container(
      height: 190,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      decoration: BoxDecoration(
        color: VoxoraColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoxoraColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Semantics(
                label:
                    '${day.words} palavras em ${labels[day.date.weekday - 1]}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      day.words == 0 ? '' : _compactNumber(day.words),
                      style: const TextStyle(
                        color: VoxoraColors.mutedStrong,
                        fontSize: 9,
                      ),
                    ),
                    const SizedBox(height: 5),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      width: 18,
                      height: maxWords == 0
                          ? 5
                          : 5 + (day.words / maxWords) * 105,
                      decoration: BoxDecoration(
                        color: day.words == 0
                            ? VoxoraColors.borderStrong
                            : VoxoraColors.accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      labels[day.date.weekday - 1],
                      style: const TextStyle(
                        color: VoxoraColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: VoxoraColors.muted, size: 20),
          const SizedBox(width: 18),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5))),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

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

String _compactNumber(int value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)} mi';
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)} mil';
  }
  return value.toString();
}

String _formatDuration(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  if (duration.inHours > 0) {
    final minutes = duration.inMinutes.remainder(60);
    return minutes == 0
        ? '${duration.inHours} h'
        : '${duration.inHours} h $minutes min';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes} min';
  return '${duration.inSeconds} s';
}
