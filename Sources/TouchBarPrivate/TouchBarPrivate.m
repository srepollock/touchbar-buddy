#import "TouchBarPrivate.h"
#import <dlfcn.h>

@interface NSTouchBarItem (TBPPrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (TBPPrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)bar systemTrayItemIdentifier:(NSString *)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)bar;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)bar;
@end

typedef void (*TBPSetPresenceFn)(NSString *identifier, BOOL present);
typedef void (*TBPCloseBoxFn)(BOOL show);

static TBPSetPresenceFn presenceFn = NULL;
static TBPCloseBoxFn closeBoxFn = NULL;
static BOOL symbolsResolved = NO;

static void resolveSymbols(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
        if (handle == NULL) {
            return;
        }
        presenceFn = (TBPSetPresenceFn)dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier");
        closeBoxFn = (TBPCloseBoxFn)dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost");
        symbolsResolved = (presenceFn != NULL && closeBoxFn != NULL);
    });
}

BOOL TBPPrivateAPIsAvailable(void) {
    resolveSymbols();
    return symbolsResolved
        && [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)]
        && [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)]
        && [NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:systemTrayItemIdentifier:)]
        && [NSTouchBar respondsToSelector:@selector(minimizeSystemModalTouchBar:)]
        && [NSTouchBar respondsToSelector:@selector(dismissSystemModalTouchBar:)];
}

void TBPSetControlStripPresence(NSString *identifier, BOOL present) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    presenceFn(identifier, present);
}

void TBPShowCloseBoxWhenFrontMost(BOOL show) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    closeBoxFn(show);
}

void TBPAddSystemTrayItem(NSTouchBarItem *item) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    [NSTouchBarItem addSystemTrayItem:item];
}

void TBPRemoveSystemTrayItem(NSTouchBarItem *item) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    [NSTouchBarItem removeSystemTrayItem:item];
}

void TBPPresentSystemModal(NSTouchBar *bar, NSString *trayIdentifier) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    [NSTouchBar presentSystemModalTouchBar:bar systemTrayItemIdentifier:trayIdentifier];
}

void TBPMinimizeSystemModal(NSTouchBar *bar) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    [NSTouchBar minimizeSystemModalTouchBar:bar];
}

void TBPDismissSystemModal(NSTouchBar *bar) {
    if (!TBPPrivateAPIsAvailable()) { return; }
    [NSTouchBar dismissSystemModalTouchBar:bar];
}
