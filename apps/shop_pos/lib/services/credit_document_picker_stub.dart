import 'package:file_picker/file_picker.dart';

Future<PlatformFile?> pickCreditDocument() {
  return FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
  );
}
