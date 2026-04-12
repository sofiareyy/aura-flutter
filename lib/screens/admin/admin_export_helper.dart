import 'admin_export_stub.dart'
    if (dart.library.html) 'admin_export_web.dart' as impl;

Future<bool> downloadAdminReport({
  required String filename,
  required String content,
}) {
  return impl.downloadAdminReport(
    filename: filename,
    content: content,
  );
}
