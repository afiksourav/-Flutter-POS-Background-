# POS Transfer Center

A Flutter POS transfer module for uploading files to the mock API, downloading
server files, and viewing active and recent transfers from a shared activity
screen.

## Run

```sh
flutter pub get
flutter run
```

Sign in with an account managed by the API. Registration is not implemented:
the supplied API contract documents `/token`, `/get`, `/upload`, and `/delete`,
but does not document a registration endpoint. The username and password are
entered at sign-in and are not stored; only the returned bearer token is kept
in platform secure storage.

## Transfer behavior

- Uploads use a native-backed `UploadTask` with multipart field `file`, progress
  updates, retries, and a system notification.
- Downloads use the `/get?file=NAME` endpoint, app Documents/Downloads storage,
  retry support, background notifications, and pause/resume. The API's documented
  `Range` support (`curl -C -`) allows the native download worker to resume a
  partial download when the server and operating system retain the partial data.
- The Activity tab shows active and recent tasks across all three tabs. Task
  state and progress are restored from the background-downloader task database.
- Notification permission is requested when the first transfer is started. If
  it is denied, transfers continue in the app and in the background where the
  OS permits, but system-tray alerts are unavailable until enabled in settings.

## Platform limits

`background_downloader` uses Android WorkManager/native job services and iOS
background `URLSession` tasks, so transfers are not tied to the current Flutter
screen and can continue when the app is backgrounded or its process is reclaimed.
The operating system still controls scheduling, execution time, and network
availability. iOS may defer work and cannot guarantee continuous execution;
Android battery restrictions and force-stop can also prevent work. Force
quitting/stopping the app may interrupt tasks, although tracked tasks are
reconciled on the next launch.

The mock upload API accepts a normal multipart `POST` and does not document a
resumable/chunked upload protocol. Therefore an upload cannot be paused and
resumed safely; failed uploads are retried by sending the file again from byte
zero. Download pause/resume is available when the API can honor byte-range
requests.

The configured mock API uses plain HTTP. Android cleartext access and an iOS
App Transport Security exception are enabled for this demo. Use HTTPS and
remove these exceptions before production deployment.

## API configuration

The base URL is in `lib/services/pos_api.dart`. The documented endpoints are:

| Action | Request |
| --- | --- |
| Sign in | `POST /token` with form-encoded `username` and `password` |
| List files | `GET /get` with `Authorization: Bearer TOKEN` |
| Upload | `POST /upload` multipart field `file` |
| Download | `GET /get?file=NAME` with bearer authorization |

## Saved downloads

Files are saved to the app-private `Documents/Downloads` directory. This does
not require broad storage access and is readable by the app; whether users can
browse that private directory directly depends on the platform. For a public
Android Downloads entry or iOS Files visibility, add an explicit export/share
flow using the platform's scoped-storage/document-picker APIs.
