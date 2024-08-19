## 0.0.3

* Add CI
* Publish tags automatically from GitHub
* Stricter analysis options

## 0.0.2

* Switch to new Flutter 3.24.0 Navigator API: `onDidRemovePage`
  * Make use of `Page.canPop` and `Page.onPopInvoke` to tell the framework which pages can be popped.  
    This can be configured / changed during the page's display, e.g. to prevent back swipes once a form contains changes.

## 0.0.1

* Initial release with basic page and navigtable source ("bloc for routing") support
