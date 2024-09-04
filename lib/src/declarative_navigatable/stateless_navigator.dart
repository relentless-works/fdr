import 'package:fdr/fdr.dart';

abstract class StatelessNavigator extends MappedNavigatableSource<void> {
  StatelessNavigator() : super(initialState: null);

  @override
  List<DeclarativeNavigatable> build();
}
