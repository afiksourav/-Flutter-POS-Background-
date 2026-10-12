import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/remote_file.dart';
import '../models/transfer_item.dart';
import '../services/pos_api.dart';
import '../state/transfer_controller.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.token, required this.api, required this.onLogout});

  final String token;
  final PosApi api;
  final VoidCallback onLogout;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final TransferController _controller = TransferController(widget.api);
  int _selectedIndex = 0;
  int _lastNotificationTapVersion = 0;

  static const _titles = ['Upload files', 'Downloads', 'Transfer activity'];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  void _onControllerChanged() {
    if (_controller.notificationTapVersion != _lastNotificationTapVersion) {
      _lastNotificationTapVersion = _controller.notificationTapVersion;
      setState(() => _selectedIndex = 2);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _UploadPage(controller: _controller, onViewActivity: () => setState(() => _selectedIndex = 2)),
      _DownloadsPage(controller: _controller),
      _ActivityPage(controller: _controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex], style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: _ActiveTransfersBadge(
                  count: _controller.activeCount,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account options',
            onSelected: (value) {
              if (value == 'signout') widget.onLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'signout',
                child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout), title: Text('Sign out')),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Column(
          children: [
            if (_controller.initializationError != null)
              _InlineNotice(message: _controller.initializationError!, onRetry: _controller.initialize),
            if (!_controller.notificationPermissionGranted && _controller.initialized && _controller.activeCount > 0)
              const _InlineNotice(message: 'Enable notifications to see transfer updates in the tray.'),
            Expanded(
              child: IndexedStack(index: _selectedIndex, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            selectedIcon: Icon(Icons.cloud_upload_rounded),
            label: 'Upload',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download_rounded),
            label: 'Download',
          ),
          NavigationDestination(
            icon: Icon(Icons.swap_vert_rounded),
            selectedIcon: Icon(Icons.swap_vert_rounded),
            label: 'Activity',
          ),
        ],
      ),
    );
  }
}

class _UploadPage extends StatelessWidget {
  const _UploadPage({required this.controller, required this.onViewActivity});

  final TransferController controller;
  final VoidCallback onViewActivity;

  Future<void> _chooseFile(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false, withData: false);
      if (result == null) return;
      final file = result.files.single;
      final filePath = file.path;
      if (filePath == null || filePath.isEmpty) {
        throw const TransferException(
          'This file provider did not expose a readable file. Save a local copy and try again.',
        );
      }
      await controller.enqueueUpload(filePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${file.name} added to the upload queue')));
      }
    } on TransferException catch (error) {
      if (context.mounted) _showError(context, error.message);
    } on FileSystemException {
      if (context.mounted) {
        _showError(context, 'The selected file could not be read.');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, 'Could not select this file. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final recent = controller.transfers.take(2).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF123C4A), Color(0xFF167D75)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 30),
              const SizedBox(height: 20),
              Text(
                'Move your business data',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Upload product catalogs, videos, and audit exports securely.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.82)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => _chooseFile(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF123C4A),
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Choose a file to upload'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Built for large files', subtitle: 'Transfers run independently of this screen.'),
        const SizedBox(height: 10),
        const _FeatureRow(
          icon: Icons.cloud_sync_outlined,
          title: 'Background transfer',
          subtitle: 'Keep working while native services handle uploads.',
        ),
        const _FeatureRow(
          icon: Icons.notifications_active_outlined,
          title: 'System notifications',
          subtitle: 'See completion and return to transfer activity.',
        ),
        const _FeatureRow(
          icon: Icons.lock_outline,
          title: 'Protected sign-in',
          subtitle: 'Your API token is stored in platform secure storage.',
        ),
        const SizedBox(height: 22),
        _SectionHeading(
          title: 'Recent transfers',
          subtitle: recent.isEmpty ? 'Your transfers will appear here.' : null,
          action: recent.isEmpty ? null : TextButton(onPressed: onViewActivity, child: const Text('View all')),
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const _EmptyPanel(
            icon: Icons.cloud_done_outlined,
            title: 'Ready when you are',
            message: 'Choose a file to start your first upload.',
          )
        else
          ...recent.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TransferCard(item: item, controller: controller),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _DownloadsPage extends StatelessWidget {
  const _DownloadsPage({required this.controller});

  final TransferController controller;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: controller.refreshFiles,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeading(title: 'Server files', subtitle: 'Download a file saved by your POS account.'),
              ),
              IconButton(
                tooltip: 'Refresh files',
                onPressed: controller.loadingFiles ? null : controller.refreshFiles,
                icon: controller.loadingFiles
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          if (controller.filesError != null) ...[
            const SizedBox(height: 12),
            _InlineNotice(message: controller.filesError!, onRetry: controller.refreshFiles),
          ],
          const SizedBox(height: 14),
          if (controller.loadingFiles && controller.remoteFiles.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controller.remoteFiles.isEmpty)
            const _EmptyPanel(
              icon: Icons.folder_open_outlined,
              title: 'No files found',
              message: 'Upload a file first, then refresh this list.',
            )
          else
            ...controller.remoteFiles.map((file) => _RemoteFileCard(file: file, controller: controller)),
          const SizedBox(height: 14),
          const _InfoBox(
            icon: Icons.folder_outlined,
            text: 'Downloads are saved in the app’s Documents/Downloads folder.',
          ),
        ],
      ),
    );
  }
}

class _ActivityPage extends StatelessWidget {
  const _ActivityPage({required this.controller});

  final TransferController controller;

  @override
  Widget build(BuildContext context) {
    final items = controller.transfers;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SectionHeading(
          title: 'All transfers',
          subtitle: '${controller.activeCount} in progress',
          action: items.isNotEmpty
              ? IconButton(
                  tooltip: 'Refresh server files',
                  onPressed: controller.refreshFiles,
                  icon: const Icon(Icons.refresh),
                )
              : null,
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          const _EmptyPanel(
            icon: Icons.swap_vert_rounded,
            title: 'No transfer activity yet',
            message: 'Uploads and downloads will show up here.',
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TransferCard(item: item, controller: controller),
            ),
          ),
        if (!controller.notificationPermissionGranted && controller.initialized)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _InfoBox(
              icon: Icons.notifications_off_outlined,
              text:
                  'System notifications are unavailable. Allow notifications in device settings to see completion alerts.',
            ),
          ),
      ],
    );
  }
}

class _RemoteFileCard extends StatelessWidget {
  const _RemoteFileCard({required this.file, required this.controller});

  final RemoteFile file;
  final TransferController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            const _IconTile(icon: Icons.insert_drive_file_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Available on server',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Download ${file.name}',
              onPressed: () async {
                try {
                  await controller.enqueueDownload(file);
                } on TransferException catch (error) {
                  if (context.mounted) _showError(context, error.message);
                } catch (_) {
                  if (context.mounted) {
                    _showError(context, 'Could not start this download.');
                  }
                }
              },
              icon: const Icon(Icons.download_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.item, required this.controller});

  final TransferItem item;
  final TransferController controller;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isUpload = item.kind == TransferKind.upload;
    final isActive = !item.status.isFinalState;
    final percentage = (item.progress * 100).round().clamp(0, 100);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _IconTile(
                  icon: isUpload ? Icons.cloud_upload_outlined : Icons.download_for_offline_outlined,
                  color: isUpload ? colors.primary : const Color(0xFF315E9E),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isUpload ? 'Upload' : 'Download'} · ${_statusLabel(item.status)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _statusColor(item.status, colors),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _transferAction(context),
              ],
            ),
            if (isActive || item.status == TaskStatus.complete) ...[
              const SizedBox(height: 15),
              LinearProgressIndicator(
                value: item.progress.clamp(0, 1),
                minHeight: 7,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: colors.surfaceContainerHighest,
              ),
              const SizedBox(height: 7),
              Text(
                item.status == TaskStatus.complete ? '100% · Complete' : '$percentage% complete',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            if (item.errorMessage != null) ...[
              const SizedBox(height: 9),
              Text(item.errorMessage!, style: TextStyle(color: colors.error, fontSize: 12)),
            ],
            if (item.status == TaskStatus.complete && item.kind == TransferKind.download)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Saved to Documents/Downloads',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            if (isUpload && isActive)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Uploads cannot be paused by this server; they can be retried if interrupted.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _transferAction(BuildContext context) {
    if (item.canPause) {
      return IconButton(
        tooltip: 'Pause download',
        onPressed: () => _runAction(context, controller.pause(item)),
        icon: const Icon(Icons.pause_circle_outline_rounded),
      );
    }
    if (item.canResume) {
      return IconButton(
        tooltip: 'Resume download',
        onPressed: () => _runAction(context, controller.resume(item)),
        icon: const Icon(Icons.play_circle_outline_rounded),
      );
    }
    if (item.status == TaskStatus.failed || item.status == TaskStatus.notFound || item.status == TaskStatus.canceled) {
      return IconButton(
        tooltip: 'Retry transfer',
        onPressed: () => _runAction(context, controller.retry(item)),
        icon: const Icon(Icons.refresh_rounded),
      );
    }
    return const SizedBox(width: 44, height: 44);
  }
}

Future<void> _runAction(BuildContext context, Future<void> action) async {
  try {
    await action;
  } on TransferException catch (error) {
    if (context.mounted) _showError(context, error.message);
  } catch (_) {
    if (context.mounted) {
      _showError(context, 'Transfer action failed. Please try again.');
    }
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

String _statusLabel(TaskStatus status) => switch (status) {
  TaskStatus.enqueued => 'Queued',
  TaskStatus.running => 'In progress',
  TaskStatus.complete => 'Complete',
  TaskStatus.notFound => 'File not found',
  TaskStatus.failed => 'Failed',
  TaskStatus.canceled => 'Canceled',
  TaskStatus.waitingToRetry => 'Retrying',
  TaskStatus.paused => 'Paused',
};

Color _statusColor(TaskStatus status, ColorScheme colors) => switch (status) {
  TaskStatus.complete => const Color(0xFF167D55),
  TaskStatus.failed || TaskStatus.notFound => colors.error,
  TaskStatus.paused => const Color(0xFF8A641B),
  _ => colors.onSurfaceVariant,
};

class _ActiveTransfersBadge extends StatelessWidget {
  const _ActiveTransfersBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.sync_rounded, size: 17),
      label: Text('$count active'),
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.subtitle, this.action});

  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _IconTile(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: tint, size: 21),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9EDF2)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer, fontSize: 12)),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
