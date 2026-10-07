import 'favicon_service_stub.dart'
    if (dart.library.html) 'favicon_service_web.dart' as platform;

/// Updates the browser tab icon when a shop selects a brand logo.
///
/// Native platforms keep using their app icon; this only changes Flutter Web.
class FaviconService {
  static void update(String? imageSource) => platform.updateFavicon(imageSource);
}
