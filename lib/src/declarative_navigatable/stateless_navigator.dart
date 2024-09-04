import 'package:fdr/fdr.dart';

abstract class StatelessNavigator extends StatefulNavigator {
  List<DeclarativeNavigatable> build();

  @override
  StatefulNavigatorState<StatefulNavigator> createState() =>
      _StatelessNavigatorState();
}

class _StatelessNavigatorState extends StatefulNavigatorState {
  @override
  List<DeclarativeNavigatable> build() {
    return (navigator as StatelessNavigator).build();
  }
}
