// Host-only UI driver for the pinned Cypherpunk SDL simulator.
#import <AppKit/AppKit.h>
#import <Vision/Vision.h>
#include <SDL2/SDL.h>
#include "account_manager.h"
#include "device_setting.h"
#include "gui_framework.h"
#include "gui_views.h"
#include "secret_cache.h"

int ProvisionFixture(void)
{
    // BIP39 entropy of the public Speculos mnemonic used by signer.c.
    uint8_t entropy[] = {
        0x63, 0x95, 0x86, 0x1d, 0x38, 0x51, 0x0e, 0xad,
        0xd4, 0x42, 0xa2, 0xec, 0xb3, 0x57, 0xa3, 0x5b,
        0xc7, 0xe1, 0xd5, 0xd2, 0x5c, 0x7a, 0xc4, 0xb2,
        0x52, 0xb7, 0x36, 0x22, 0xe3, 0xf6, 0x2c, 0x4e,
    };
    uint8_t accounts;
    bool cleanup = false;
    if (GetExistAccountNum(&accounts) != 0 || accounts != 0) return EXIT_FAILURE;
    SecretCacheSetWalletName("QR fixture");
    if (CreateNewAccount(0, entropy, sizeof(entropy), "123456", &cleanup) != 0) return EXIT_FAILURE;
    return SaveSetupCheckpoint(SETUP_PHASE_DONE) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

static NSWindow *SimulatorWindow(void)
{
    for (NSWindow *window in NSApp.windows) {
        if ([window.title isEqualToString:@"TFT Simulator"]) return window;
    }
    return nil;
}

static bool ReviewIsReady(NSWindow *window, NSString *title)
{
    // Capture only this SDL window. The GUI reader independently captures the
    // primary display to find and decode the QR shown by Flutter.
    NSString *path = @"scan-window.png";
    NSTask *capture = [[NSTask alloc] init];
    capture.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
    capture.arguments = @[@"-x", @"-o", @"-l", @(window.windowNumber).stringValue, path];
    if (![capture launchAndReturnError:NULL]) return false;
    [capture waitUntilExit];
    if (capture.terminationStatus != 0) return false;

    VNRecognizeTextRequest *text = [[VNRecognizeTextRequest alloc] init];
    text.recognitionLanguages = @[@"en-US"];
    VNImageRequestHandler *reader = [[VNImageRequestHandler alloc]
        initWithURL:[NSURL fileURLWithPath:path] options:@{}];
    if (![reader performRequests:@[text] error:NULL]) return false;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (VNRecognizedTextObservation *line in text.results) {
        NSString *value = [line topCandidates:1].firstObject.string;
        if (value) [lines addObject:value];
    }
    // A single PCZT opens its review shell before the asynchronous parser
    // fills in the amount and fee. Keep driving LVGL through that transition.
    NSString *content = [lines componentsJoinedByString:@" "];
    NSString *zecAmount = @"[0-9]+([.,][0-9]+)?\\s+ZEC";
    return [lines containsObject:title] && [content containsString:@"Amount"] &&
           [content containsString:@"Fee"] &&
           [content rangeOfString:zecAmount options:NSRegularExpressionSearch].location != NSNotFound;
}

void DriveScan(const char *kind)
{
    static unsigned eventIndex;
    static Uint64 nextEvent;
    static bool scanStarted;
    Uint64 now = SDL_GetTicks64();
    if (now < nextEvent) return;

    GUI_VIEW *review = strcmp(kind, "single") == 0 ? &g_transactionDetailView : &g_zcashBatchView;
    if (scanStarted && GuiCheckIfTopView(review)) {
        NSString *title = strcmp(kind, "vote") == 0 ? @"Confirm Transaction (1/2)" : @"Confirm Transaction";
        lv_refr_now(NULL);
        if (!ReviewIsReady(SimulatorWindow(), title)) {
            nextEvent = SDL_GetTicks64() + 200;
            return;
        }
        if (rename("scan-window.png", "review.png") != 0) exit(EXIT_FAILURE);
        printf("Keystone GUI review: %s\n", title.UTF8String);
        exit(EXIT_SUCCESS);
    }

    // Press and release the six fixture PIN digits, then the orange Scan button.
    static const SDL_Point taps[] = {
        {83, 447}, {240, 447}, {396, 447}, {83, 523}, {240, 523}, {396, 523}, {385, 709}
    };
    unsigned tap = eventIndex / 2;
    if (tap >= sizeof(taps) / sizeof(taps[0])) return;
    if (eventIndex == 0) {
        if (!GuiCheckIfTopView(&g_lockView)) return;
        NSWindow *window = SimulatorWindow();
        if (!window) return;
        NSRect screen = NSScreen.screens.firstObject.visibleFrame;
        [window setFrameTopLeftPoint:NSMakePoint(NSMinX(screen), NSMaxY(screen))];
        [window setLevel:NSFloatingWindowLevel];
        [window orderFrontRegardless];
    }
    if (eventIndex == 12) {
        if (!GuiCheckIfTopView(&g_homeView)) return;
        scanStarted = true;
    }
    SDL_Event event = {0};
    event.type = eventIndex % 2 == 0 ? SDL_MOUSEBUTTONDOWN : SDL_MOUSEBUTTONUP;
    event.button.button = SDL_BUTTON_LEFT;
    event.button.x = taps[tap].x;
    event.button.y = taps[tap].y;
    if (SDL_PushEvent(&event) < 0) exit(EXIT_FAILURE);
    eventIndex++;
    nextEvent = now + 100;
}
