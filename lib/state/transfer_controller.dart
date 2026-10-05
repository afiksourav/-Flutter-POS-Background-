import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../models/remote_file.dart';
import '../models/transfer_item.dart';
import '../services/pos_api.dart';

class TransferController extends ChangeNotifier {
  TransferController(this._api);

  static const _group = 'pos-transfers';
  static const _downloadFolder = 'Downloads';
  final PosApi _api;
  final FileDownloader _downloader = FileDownloader();
  final Map<String, TransferItem> _items = {};
  List<RemoteFile> _remoteFiles = [];
  bool _initialized = false;
  bool _loadingFiles = false;
  bool _notificationPermissionGranted = false;
  bool _permissionAsked = false;
  String? _initializationError;
  String? _filesError;
  int _notificationTapVersion = 0;

  List<TransferItem> get transfers {
    final values = _items.values.toList()..sort((a, b) => b.task.creationTime.compareTo(a.task.creationTime));
    return values;
  }

  List<RemoteFile> get remoteFiles => List.unmodifiable(_remoteFiles);
  bool get initialized => _initialized;
  bool get loadingFiles => _loadingFiles;
  bool get notificationPermissionGranted => _notificationPermissionGranted;
  String? get initializationError => _initializationError;
  String? get filesError => _filesError;
  int get notificationTapVersion => _notificationTapVersion;

  int get activeCount => _items.values.where((item) => !item.status.isFinalState).length;

  @override
  void dispose() {
    _downloader.unregisterCallbacks(group: _group);
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      await _downloader.ready;
      _downloader.registerCallbacks(
        group: _group,
        taskStatusCallback: _onStatus,
        taskProgressCallback: _onProgress,
        taskNotificationTapCallback: (task, _) {
          _notificationTapVersion++;
          notifyListeners();
        },
      );
      _downloader.configureNotificationForGroup(
        _group,
        running: const TaskNotification('Transfer in progress', '{displayName} • {progress}'),
        complete: const TaskNotification('Transfer complete', '{displayName} is ready'),
        error: const TaskNotification('Transfer needs attention', '{displayName}'),
        paused: const TaskNotification('Transfer paused', '{displayName}'),
        progressBar: true,
      );
      await _downloader.trackTasks();
      await _downloader.resumeFromBackground();
      await _downloader.rescheduleKilledTasks();
      final records = await _downloader.database.allRecords(group: _group);
      for (final record in records) {
        final task = record.task;
        _items[task.taskId] = TransferItem(
          task: task,
          kind: task is UploadTask ? TransferKind.upload : TransferKind.download,
          status: record.status,
          progress: record.progress.clamp(0.0, 1.0).toDouble(),
          errorMessage: record.exception?.description,
          remoteFile: _remoteFileForTask(task),
        );
      }
      _initialized = true;
      notifyListeners();
      await refreshFiles();
    } catch (error) {
      _initializationError = 'Background transfers could not be initialized. $error';
      notifyListeners();
    }
  }

  Future<void> refreshFiles() async {
    _loadingFiles = true;
    _filesError = null;
    notifyListeners();
    try {
      _remoteFiles = await _api.listFiles();
    } catch (error) {
      _filesError = _userMessage(error);
    } finally {
      _loadingFiles = false;
      notifyListeners();
    }
  }

  Future<void> enqueueUpload(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const TransferException('This file is no longer available. Select it again to upload.');
    }
    final length = await file.length();
    if (length <= 0) {
      throw const TransferException('The selected file is empty.');
    }
    await _requestNotificationPermission();
    final name = filePath.split(RegExp(r'[/\\]')).last;
    final task = UploadTask.fromFile(
      file: file,
      url: '${PosApi.baseUrl}upload',
      headers: {'Authorization': 'Bearer ${_api.token}'},
      fileField: 'file',
      group: _group,
      displayName: name,
      updates: Updates.statusAndProgress,
      retries: 3,
    );
    _items[task.taskId] = TransferItem(task: task, kind: TransferKind.upload, status: TaskStatus.enqueued);
    notifyListeners();
    if (!await _downloader.enqueue(task)) {
      _items[task.taskId] = _items[task.taskId]!.copyWith(
        status: TaskStatus.failed,
        errorMessage: 'Could not queue this upload. Please try again.',
      );
      notifyListeners();
      throw const TransferException('The upload could not be queued. Please try again.');
    }
  }

  Future<void> enqueueDownload(RemoteFile file) async {
    await _requestNotificationPermission();
    final task = DownloadTask(
      url: _api.downloadUrl(file),
      urlQueryParameters: file.url == null ? _api.downloadQuery(file) : null,
      filename: file.name,
      headers: {'Authorization': 'Bearer ${_api.token}'},
      baseDirectory: BaseDirectory.applicationDocuments,
      directory: _downloadFolder,
      group: _group,
      displayName: file.name,
      allowPause: true,
      updates: Updates.statusAndProgress,
      retries: 5,
    );
    _items[task.taskId] = TransferItem(
      task: task,
      kind: TransferKind.download,
      status: TaskStatus.enqueued,
      remoteFile: file,
    );
    notifyListeners();
    if (!await _downloader.enqueue(task)) {
      _items[task.taskId] = _items[task.taskId]!.copyWith(
        status: TaskStatus.failed,
        errorMessage: 'Could not queue this download. Please try again.',
      );
      notifyListeners();
      throw const TransferException('The download could not be queued. Please try again.');
    }
  }

  Future<void> pause(TransferItem item) async {
    if (item.task is! DownloadTask || !await _downloader.pause(item.task as DownloadTask)) {
      throw const TransferException('This transfer cannot be paused. The server must support byte ranges.');
    }
  }

  Future<void> resume(TransferItem item) async {
    if (item.task is! DownloadTask || !await _downloader.resume(item.task as DownloadTask)) {
      throw const TransferException('The transfer could not be resumed. Try again or restart it.');
    }
  }

  Future<void> retry(TransferItem item) async {
    if (item.kind == TransferKind.upload) {
      await enqueueUpload(await item.task.filePath());
      return;
    }
    final file = item.remoteFile ?? _remoteFileForTask(item.task);
    if (file == null) {
      throw const TransferException(
        'The original server file could not be identified. Refresh the file list and try again.',
      );
    }
    await enqueueDownload(file);
  }

  Future<void> _requestNotificationPermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    final status = await _downloader.permissions.request(PermissionType.notifications);
    _notificationPermissionGranted = status == PermissionStatus.granted;
    notifyListeners();
  }

  void _onProgress(TaskProgressUpdate update) {
    final item = _items[update.task.taskId];
    if (item == null || update.progress < 0) return;
    _items[item.id] = item.copyWith(progress: update.progress);
    notifyListeners();
  }

  void _onStatus(TaskStatusUpdate update) {
    final existing = _items[update.task.taskId];
    final task = update.task;
    final kind = task is UploadTask ? TransferKind.upload : TransferKind.download;
    var item =
        existing ?? TransferItem(task: task, kind: kind, status: update.status, remoteFile: _remoteFileForTask(task));
    String? errorMessage;
    if (update.status == TaskStatus.failed || update.status == TaskStatus.notFound) {
      errorMessage = _statusMessage(update);
    }
    RemoteFile? remoteFile = item.remoteFile;
    if (update.status == TaskStatus.complete && task is UploadTask) {
      final name = _api.uploadedFileName(update.responseBody);
      if (name != null) remoteFile = RemoteFile(name: name);
    }
    item = item.copyWith(
      task: task,
      status: update.status,
      progress: update.status == TaskStatus.complete ? 1 : item.progress,
      errorMessage: errorMessage,
      clearError: errorMessage == null,
      remoteFile: remoteFile,
    );
    _items[task.taskId] = item;
    notifyListeners();
    if (update.status == TaskStatus.complete && task is UploadTask) {
      refreshFiles();
    }
  }

  String _statusMessage(TaskStatusUpdate update) {
    final code = update.responseStatusCode;
    if (code == 401 || code == 403) {
      return 'Authentication expired. Sign in again and retry.';
    }
    if (code == 404) return 'The requested file was not found on the server.';
    if (code != null && code >= 500) {
      return 'The server is temporarily unavailable. Please retry.';
    }
    return 'Transfer failed. Check your connection and retry.';
  }

  RemoteFile? _remoteFileForTask(Task task) {
    if (task is! DownloadTask) return null;
    final name = Uri.tryParse(task.url)?.queryParameters['file'];
    if (name == null || name.isEmpty) return null;
    return RemoteFile(name: name);
  }

  String _userMessage(Object error) {
    if (error is PosApiException) return error.message;
    if (error is TransferException) return error.message;
    return 'Something went wrong. Check your connection and try again.';
  }
}

class TransferException implements Exception {
  const TransferException(this.message);

  final String message;

  @override
  String toString() => message;
}
