// ignore: deprecated_member_use
import 'dart:html' as html;

void updateFavicon(String? imageSource) {
  final source = imageSource?.trim();
  final useDefault = source == null || source.isEmpty;
  final href = useDefault ? 'favicon.png' : source;

  final link = html.document.querySelector('#app-favicon') as html.LinkElement? ??
      (html.document.querySelector('link[rel~="icon"]') as html.LinkElement? ??
          (html.LinkElement()
            ..rel = 'icon'
            ..type = 'image/png'
            ..id = 'app-favicon'));

  link.href = href;
  if (useDefault) {
    link.type = 'image/png';
  } else {
    link.removeAttribute('type');
  }
  if (link.parentNode == null) html.document.head?.append(link);
}
