import 'package:fdr/fdr.dart';
import 'package:fdr/src/navigatable_to_page_mapper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

part 'declarative_navigatable_page.dart';
part 'disposable_navigatable.dart';
part 'navigatable_source.dart';
part 'pop_overwrite_navigatable.dart';
part 'stateful_navigator.dart';

sealed class DeclarativeNavigatable {}

extension Poppable on DeclarativeNavigatable {
  DeclarativeNavigatable poppable({required VoidCallback? onPop}) {
    return PopOverwriteNavigatable(this, onPop: onPop);
  }
}
