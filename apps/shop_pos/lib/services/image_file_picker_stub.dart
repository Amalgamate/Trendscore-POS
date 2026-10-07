import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart' show FilePickerWebOptions;

/// Non-web fallback (Android / desktop): uses the file_picker plugin.
/// Returns null if the user cancelled.
Future<Uint8List?> pickImageBytes() async {
  final file = await FilePicker.pickFile(
    type: FileType.image,
    webOptions: const FilePickerWebOptions(cancelUploadOnWindowBlur: false),
  );
  if (file == null) return null;
  return file.readAsBytes();
}
