/// Declarative (state-driven) routing for Flutter, with a typed URL layer.
library;

export 'src/core/core.dart'
    show
        DeclarativeNavigatable,
        DeclarativeNavigatablePage,
        FdrHotReload,
        HistoryAction,
        KeyedPage,
        MountNavigator,
        MountNavigatorWithLens,
        MountedNavigatable,
        RouteLens,
        NavigatableToPageMapper,
        PageBuilder,
        PopOverwriteNavigatable,
        Poppable,
        RoutingScope,
        ShellBuilder,
        ShellNavigatable,
        StatefulNavigator,
        StatefulNavigatorState,
        StatelessNavigator;
export 'src/async_navigator.dart' show AsyncChildBuilder, AsyncNavigator;
export 'src/declarative_navigator.dart' show DeclarativeNavigator;
export 'src/routing/browser_history.dart' show BrowserHistory, NoBrowserHistory;
export 'src/routing/fdr_router.dart'
    show
        FdrRouteInformationParser,
        FdrRouteInformationProvider,
        FdrRouter,
        FdrRouterDelegate,
        RouteSnapshot;
export 'src/routing/lens_codec.dart';
export 'src/routing/url_codec.dart';
export 'src/widget_extensions.dart'
    show DeclarativeNavigatableFromWidget, shell;
