import 'package:background_downloader/background_downloader.dart';

import 'remote_file.dart';

enum TransferKind { upload, download }

class TransferItem {
  const TransferItem({
    required this.task,
    required this.kind,
    required this.status,
    this.progress = 0,
    this.errorMessage,
    this.remoteFile,
  });

  final Task task;
  final TransferKind kind;
  final TaskStatus status;
  final double progress;
  final String? errorMessage;
  final RemoteFile? remoteFile;

  String get id => task.taskId;

  String get filename {
    final name = task.displayName.isNotEmpty ? task.displayName : task.filename;
    return name.split(RegExp(r'[/\\]')).last;
  }

  bool get canPause => kind == TransferKind.download &&
      status == TaskStatus.running &&
      task is DownloadTask;

  bool get canResume => kind == TransferKind.download &&
      status == TaskStatus.paused &&
      task is DownloadTask;

  TransferItem copyWith({
    Task? task,
    TaskStatus? status,
    double? progress,
    String? errorMessage,
    bool clearError = false,
    RemoteFile? remoteFile,
  }) {
    return TransferItem(
      task: task ?? this.task,
      kind: kind,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      remoteFile: remoteFile ?? this.remoteFile,
    );
  }
}
