#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

void TBPSetControlStripPresence(NSString *identifier, BOOL present);
void TBPShowCloseBoxWhenFrontMost(BOOL show);
void TBPAddSystemTrayItem(NSTouchBarItem *item);
void TBPRemoveSystemTrayItem(NSTouchBarItem *item);
void TBPPresentSystemModal(NSTouchBar *bar, NSString *trayIdentifier);
void TBPMinimizeSystemModal(NSTouchBar *bar);
void TBPDismissSystemModal(NSTouchBar *bar);
BOOL TBPPrivateAPIsAvailable(void);

NS_ASSUME_NONNULL_END
