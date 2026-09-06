import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool get isGoogleMapsJavascriptReady {
  if (!globalContext.hasProperty('google'.toJS).toDart) return false;
  final google = globalContext.getProperty<JSObject>('google'.toJS);
  return google.hasProperty('maps'.toJS).toDart;
}
