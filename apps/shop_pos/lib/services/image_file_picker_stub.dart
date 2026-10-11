import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

/// Non-web fallback (Android / desktop): uses the file_picker plugin.
/// Returns null if the user cancelled.
Future<Uint8List?> pickImageBytes() async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null;
  return file.readAsBytes();
}
