/// Declarative (state-driven) routing for Flutter, with typed URLs.
library;

export 'src/core/core.dart'
    show
        CustomPage,
        CustomPageBuilder,
        DeclarativeNavigator,
        DialogPage,
        HistoryAction,
        NavEntry,
        NavPage,
        NestedNavigator,
        RouteLink,
        RouteLinkBuilder,
        StatefulNavigator,
        StatefulNavigatorState,
        StatelessNavigator,
        TabsBuilder,
        TabsPage;
export 'src/future_navigator.dart' show FutureChildBuilder, FutureNavigator;
export 'src/routing/browser_history.dart' show BrowserHistory, NoBrowserHistory;
export 'src/routing/fdr_router.dart' show FdrRouter, RouteSnapshot;
export 'src/routing/url.dart' show NavRoute, NotFound, Url;
