import '../core/core.dart';
import 'url_codec.dart';

extension EmbeddedCodec<C> on UrlCodec<C> {
  /// Lifts this child codec into the parent's route type through [lens].
  LensCase<P, C> embedded<P>(RouteLens<P, C> lens) {
    return LensCase<P, C>(this, lens.embed);
  }
}
