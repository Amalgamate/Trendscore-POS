import 'package:file_picker/file_picker.dart';
import 'package:file_picker_web/file_picker_web.dart' show FilePickerWebOptions;

Future<PlatformFile?> pickCreditDocument() {
  return FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    webOptions: const FilePickerWebOptions(cancelUploadOnWindowBlur: false),
  );
}
