/// Declarative (state-driven) routing for Flutter
library fdr;

export './src/declarative_navigatable/declarative_navigatable.dart'
    show
        DeclarativeNavigatable,
        DeclarativeNavigatablePage,
        PageBuilder,
        Poppable,
        StatefulNavigator,
        StatefulNavigatorState,
        PopOverwriteNavigatable;
export './src/declarative_navigatable/stateless_navigator.dart'
    show StatelessNavigator;
export './src/declarative_navigator.dart' show DeclarativeNavigator;
export './src/pages/fdr_page.dart' show FDRPage;
export './src/widget_extensions.dart' show DeclarativeNavigatableFromWidget;
