/// Declarative (state-driven) routing for Flutter
library fdr;

export './src/declarative_navigatable/declarative_navigatable.dart'
    show
        DeclarativeNavigatable,
        DeclarativeNavigatablePage,
        NavigatableSource,
        PageBuilder,
        Poppable,
        StatefulNavigator,
        StatefulNavigatorState,
        DisposableNavigatable,
        PopOverwriteNavigatable;
export './src/declarative_navigatable/mapped_navigatable_source.dart'
    show MappedNavigatableSource;
export './src/declarative_navigator.dart' show DeclarativeNavigator;
export './src/pages/fdr_page.dart' show FDRPage;
export './src/widget_extensions.dart' show DeclarativeNavigatableFromWidget;
