/// Declarative (state-driven) routing for Flutter
library fdr;

export './src/declarative_navigator.dart'
    show
        DeclarativeNavigatable,
        DeclarativeNavigatableFromWidget,
        DeclarativeNavigatablePage,
        DeclarativeNavigator,
        MappedNavigatableSource,
        NavigatableSource,
        PageBuilder,
        Poppable,
        StatefulNavigator,
        StatefulNavigatorState;
export './src/pages/fdr_page.dart' show FDRPage;
