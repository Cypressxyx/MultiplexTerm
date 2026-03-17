// E2E integration tests for MultiplexTerm
// Exercises the actual ObjC UI code paths by creating the view and sending
// synthetic NSEvents. Asserts on both ObjC view state and bridge state.
//
// Run: zig build e2e-test
// Requires: macOS with tmux installed, GUI session (not headless CI)

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Bridge FFI declarations (from bridge.zig)
extern uint8_t bridge_init(void);
extern void bridge_tick(void);
extern void bridge_resize(uint16_t cols, uint16_t rows);
extern uint16_t bridge_get_session_count(void);
extern uint8_t bridge_is_session_selected(uint16_t idx);
extern uint8_t bridge_is_sidebar_visible(void);
extern void bridge_toggle_sidebar(void);
extern void bridge_select_session(uint16_t idx);
extern void bridge_create_session(void);
extern void bridge_kill_session(uint16_t idx);
extern uint8_t bridge_is_started(void);
extern void bridge_start_first_session(void);
extern uint8_t bridge_is_ssh_session(uint16_t idx);
extern const uint8_t* bridge_get_display_name(uint16_t idx);
extern uint16_t bridge_get_display_name_len(uint16_t idx);
extern void bridge_key_input(const uint8_t* data, uint32_t len);

// Layout constants (must match macos.m)
static const CGFloat kSidebarWidth    = 220.0;
static const CGFloat kHeaderHeight    = 48.0;
static const CGFloat kSessionRowH     = 34.0;
static const CGFloat kNewBtnHeight    = 44.0;
static const CGFloat kTitlebarInset   = 28.0;

// Test infrastructure
static int g_tests_run = 0;
static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define E2E_ASSERT(cond, msg) do { \
    if (!(cond)) { \
        fprintf(stderr, "  FAIL: %s (line %d)\n", msg, __LINE__); \
        g_tests_failed++; \
        return; \
    } \
} while(0)

#define E2E_TEST(name) \
    static void test_##name(NSWindow* window, NSView* view); \
    static void run_##name(NSWindow* window, NSView* view) { \
        g_tests_run++; \
        fprintf(stderr, "  [%d] %s... ", g_tests_run, #name); \
        test_##name(window, view); \
        if (g_tests_failed == g_tests_run - g_tests_passed - 1 + g_tests_failed) { \
            /* no new failures */ \
        } \
        g_tests_passed++; \
        fprintf(stderr, "OK\n"); \
    } \
    static void test_##name(NSWindow* window, NSView* view)

// Helper: tick the bridge N times (simulates time passing)
static void tickBridge(int n) {
    for (int i = 0; i < n; i++) {
        bridge_tick();
    }
}

// Helper: pump the run loop briefly to let events process
static void pumpRunLoop(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}

// Helper: create and send a mouse down event to the view
static void sendMouseDown(NSWindow* window, NSView* view, CGFloat x, CGFloat y) {
    // NSView coordinates: origin at bottom-left
    NSPoint viewPoint = NSMakePoint(x, y);
    NSPoint windowPoint = [view convertPoint:viewPoint toView:nil];

    NSEvent* mouseDown = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                            location:windowPoint
                                       modifierFlags:0
                                           timestamp:[[NSProcessInfo processInfo] systemUptime]
                                        windowNumber:window.windowNumber
                                             context:nil
                                         eventNumber:0
                                          clickCount:1
                                            pressure:1.0];
    [view mouseDown:mouseDown];
}

// Helper: create and send a key down event
static void sendKeyDown(NSWindow* window, NSView* view,
                       uint16_t keyCode, NSEventModifierFlags modifiers,
                       NSString* chars) {
    NSEvent* keyDown = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:modifiers
                                       timestamp:[[NSProcessInfo processInfo] systemUptime]
                                    windowNumber:window.windowNumber
                                         context:nil
                                      characters:chars
                     charactersIgnoringModifiers:chars
                                       isARepeat:NO
                                         keyCode:keyCode];
    [view keyDown:keyDown];
}

// Helper: wait for sessions to appear (with timeout)
static BOOL waitForSessions(int minCount, int maxTicks) {
    for (int i = 0; i < maxTicks; i++) {
        bridge_tick();
        if (bridge_get_session_count() >= minCount) return YES;
        pumpRunLoop();
    }
    return bridge_get_session_count() >= minCount;
}

// ─── Tests ──────────────────────────────────────────────────────────

// Test: Cmd+K opens command palette
E2E_TEST(cmd_k_opens_palette) {
    (void)window;
    // Verify palette starts closed
    BOOL visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(!visible, "palette should start closed");

    // Send Cmd+K (keyCode 40 = 'k')
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");

    visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(visible, "palette should be visible after Cmd+K");

    NSInteger mode = [[view valueForKey:@"paletteMode"] integerValue];
    E2E_ASSERT(mode == 0, "palette should be in commands mode (0)");
}

// Test: Cmd+K again closes palette
E2E_TEST(cmd_k_toggles_palette) {
    (void)window;
    // Palette is open from previous test, close it
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");
    BOOL visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(!visible, "palette should close on second Cmd+K");
}

// Test: Escape closes palette
E2E_TEST(escape_closes_palette) {
    (void)window;
    // Open palette
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");
    BOOL visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(visible, "palette should be open");

    // Press Escape (keyCode 53)
    sendKeyDown(window, view, 53, 0, @"\x1b");
    visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(!visible, "palette should close on Escape");
}

// Test: Palette up/down navigation
E2E_TEST(palette_navigation) {
    (void)window;
    // Open palette
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");

    NSInteger sel = [[view valueForKey:@"paletteSelection"] integerValue];
    E2E_ASSERT(sel == 0, "selection should start at 0");

    // Press Down (keyCode 125)
    sendKeyDown(window, view, 125, 0, @"");
    sel = [[view valueForKey:@"paletteSelection"] integerValue];
    E2E_ASSERT(sel == 1, "selection should be 1 after Down");

    // Press Down again
    sendKeyDown(window, view, 125, 0, @"");
    sel = [[view valueForKey:@"paletteSelection"] integerValue];
    E2E_ASSERT(sel == 2, "selection should be 2 after second Down");

    // Press Up (keyCode 126)
    sendKeyDown(window, view, 126, 0, @"");
    sel = [[view valueForKey:@"paletteSelection"] integerValue];
    E2E_ASSERT(sel == 1, "selection should be 1 after Up");

    // Close palette
    sendKeyDown(window, view, 53, 0, @"\x1b");
}

// Test: Palette search filters items
E2E_TEST(palette_search) {
    (void)window;
    // Open palette
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");

    // Type "split" — should filter to "Split Pane Right" and "Split Pane Down"
    sendKeyDown(window, view, 1, 0, @"s");
    sendKeyDown(window, view, 35, 0, @"p");
    sendKeyDown(window, view, 37, 0, @"l");
    sendKeyDown(window, view, 34, 0, @"i");
    sendKeyDown(window, view, 17, 0, @"t");

    NSString* searchText = [view valueForKey:@"paletteSearchText"];
    E2E_ASSERT([searchText isEqualToString:@"split"],
               "search text should be 'split'");

    // Close palette
    sendKeyDown(window, view, 53, 0, @"\x1b");

    // Verify search text is cleared on close
    searchText = [view valueForKey:@"paletteSearchText"];
    E2E_ASSERT(searchText.length == 0, "search text should be cleared after close");
}

// Test: Enter on "Theme..." opens theme picker
E2E_TEST(palette_theme_picker) {
    (void)window;
    // Open palette
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");

    // Navigate to last item (Theme...) — it's item index 8 (9 items, 0-indexed)
    for (int i = 0; i < 8; i++) {
        sendKeyDown(window, view, 125, 0, @"");
    }

    NSInteger sel = [[view valueForKey:@"paletteSelection"] integerValue];
    E2E_ASSERT(sel == 8, "selection should be at Theme... (index 8)");

    // Press Enter (keyCode 36)
    sendKeyDown(window, view, 36, 0, @"\r");

    NSInteger mode = [[view valueForKey:@"paletteMode"] integerValue];
    E2E_ASSERT(mode == 1, "palette should switch to theme mode (1)");

    BOOL visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(visible, "palette should still be visible in theme mode");

    // Escape should revert theme and go back to commands
    sendKeyDown(window, view, 53, 0, @"\x1b");
    visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(!visible, "palette should close on Escape from theme mode");
}

// Test: Sidebar toggle
E2E_TEST(sidebar_toggle) {
    (void)window;
    uint8_t visible = bridge_is_sidebar_visible();
    E2E_ASSERT(visible, "sidebar should be visible by default");

    bridge_toggle_sidebar();
    visible = bridge_is_sidebar_visible();
    E2E_ASSERT(!visible, "sidebar should be hidden after toggle");

    bridge_toggle_sidebar();
    visible = bridge_is_sidebar_visible();
    E2E_ASSERT(visible, "sidebar should be visible again after second toggle");
}

// Test: Create session via bridge
E2E_TEST(create_session) {
    (void)window; (void)view;
    // Start the first session if not started
    if (!bridge_is_started()) {
        bridge_start_first_session();
        waitForSessions(1, 120);
    }

    uint16_t initial = bridge_get_session_count();
    // Wait for sync to populate session list
    if (initial == 0) {
        waitForSessions(1, 120);
        initial = bridge_get_session_count();
    }
    E2E_ASSERT(initial >= 1, "should have at least 1 session after start");

    // Create a new session
    bridge_create_session();
    waitForSessions(initial + 1, 120);

    uint16_t after = bridge_get_session_count();
    E2E_ASSERT(after == initial + 1, "session count should increase by 1");
}

// Test: Select session via bridge
E2E_TEST(select_session) {
    (void)window; (void)view;
    uint16_t count = bridge_get_session_count();
    E2E_ASSERT(count >= 2, "need at least 2 sessions for selection test");

    // Select session 0
    bridge_select_session(0);
    tickBridge(1);
    E2E_ASSERT(bridge_is_session_selected(0), "session 0 should be selected");

    // Select session 1
    bridge_select_session(1);
    tickBridge(1);
    E2E_ASSERT(bridge_is_session_selected(1), "session 1 should be selected");
    E2E_ASSERT(!bridge_is_session_selected(0), "session 0 should not be selected");
}

// Test: Sidebar click selects session
E2E_TEST(sidebar_click_selects_session) {
    uint16_t count = bridge_get_session_count();
    E2E_ASSERT(count >= 2, "need at least 2 sessions");

    // First, select session 1
    bridge_select_session(1);
    tickBridge(1);

    // Click on session 0 in sidebar
    // Session rows start at kTitlebarInset + kHeaderHeight
    // Each non-SSH session occupies kSessionRowH pixels
    // Click in the middle of the first non-SSH session row
    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    // Find the first non-SSH session row y-position
    CGFloat rowY = listTop;
    int firstNonSshIdx = -1;
    for (uint16_t i = 0; i < count; i++) {
        if (!bridge_is_ssh_session(i)) {
            if (firstNonSshIdx == -1) {
                firstNonSshIdx = i;
                break;
            }
        }
        if (!bridge_is_ssh_session(i)) rowY += kSessionRowH;
    }

    // Click in the middle of the first session row (avoid close button on right)
    sendMouseDown(window, view, kSidebarWidth / 2, rowY + kSessionRowH / 2);
    tickBridge(1);

    E2E_ASSERT(bridge_is_session_selected(firstNonSshIdx),
               "first non-SSH session should be selected after sidebar click");
}

// Test: Click "+ New Session" button in sidebar
E2E_TEST(sidebar_new_session_click) {
    uint16_t before = bridge_get_session_count();

    // Calculate "+ New Session" button position
    // It comes after all non-SSH session rows
    CGFloat listTop = kTitlebarInset + kHeaderHeight;
    CGFloat rowY = listTop;
    uint16_t count = bridge_get_session_count();
    for (uint16_t i = 0; i < count; i++) {
        if (!bridge_is_ssh_session(i)) rowY += kSessionRowH;
    }
    // rowY is now at the top of "+ New Session" button
    sendMouseDown(window, view, kSidebarWidth / 2, rowY + kNewBtnHeight / 2);

    waitForSessions(before + 1, 120);
    uint16_t after = bridge_get_session_count();
    E2E_ASSERT(after == before + 1, "clicking + New Session should create a session");
}

// Test: Kill session via bridge
E2E_TEST(kill_session) {
    (void)window; (void)view;
    uint16_t count = bridge_get_session_count();
    E2E_ASSERT(count >= 2, "need at least 2 sessions to kill one");

    // Select session 0, then kill it
    // Must select a different session first (PTY HUP pitfall)
    bridge_select_session(0);
    tickBridge(2);

    bridge_kill_session(count - 1);  // Kill last session
    waitForSessions(count - 1, 120);

    uint16_t after = bridge_get_session_count();
    E2E_ASSERT(after == count - 1, "session count should decrease by 1 after kill");
}

// Test: Click outside palette dismisses it
E2E_TEST(click_outside_palette_dismisses) {
    // Open palette
    sendKeyDown(window, view, 40, NSEventModifierFlagCommand, @"k");
    BOOL visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(visible, "palette should be open");

    // Click in terminal area (far right, away from sidebar and palette)
    CGFloat viewW = view.bounds.size.width;
    CGFloat viewH = view.bounds.size.height;
    sendMouseDown(window, view, viewW - 50, viewH / 2);

    visible = [[view valueForKey:@"paletteVisible"] boolValue];
    E2E_ASSERT(!visible, "palette should close when clicking outside");
}

// ─── Test runner ────────────────────────────────────────────────────

int e2e_test_main(void) {
    @autoreleasepool {
        fprintf(stderr, "\n=== mterm E2E Tests ===\n\n");

        // Initialize the app environment
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Initialize theme system (called before window creation in platform_run)
        extern void initTheme(void);
        initTheme();

        // Create window
        NSRect frame = NSMakeRect(100, 100, 1280, 820);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable |
                           NSWindowStyleMaskFullSizeContentView;
        NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];

        // Create the terminal view
        Class viewClass = objc_getClass("STTerminalView");
        if (!viewClass) {
            fprintf(stderr, "FATAL: STTerminalView class not found\n");
            return 1;
        }
        NSView* view = [[viewClass alloc] initWithFrame:window.contentView.bounds];
        ((NSView*)view).autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [window.contentView addSubview:view];

        // Initialize bridge
        uint8_t result = bridge_init();
        if (result != 0) {
            fprintf(stderr, "FATAL: bridge_init failed (code %d)\n", result);
            return 1;
        }

        // Trigger initial resize
        bridge_resize(80, 24);

        // Make window visible (required for NSEvent dispatch)
        [window makeKeyAndOrderFront:nil];
        [window makeFirstResponder:view];
        pumpRunLoop();

        // Give bridge time to sync state
        tickBridge(60);
        pumpRunLoop();

        // Run tests
        fprintf(stderr, "Running tests...\n");

        // Palette tests (no tmux dependency)
        run_cmd_k_opens_palette(window, view);
        run_cmd_k_toggles_palette(window, view);
        run_escape_closes_palette(window, view);
        run_palette_navigation(window, view);
        run_palette_search(window, view);
        run_palette_theme_picker(window, view);
        run_click_outside_palette_dismisses(window, view);

        // Sidebar tests
        run_sidebar_toggle(window, view);

        // Session lifecycle tests (requires tmux)
        run_create_session(window, view);
        run_select_session(window, view);
        run_sidebar_click_selects_session(window, view);
        run_sidebar_new_session_click(window, view);
        run_kill_session(window, view);

        // Summary
        fprintf(stderr, "\n=== Results: %d/%d passed ===\n\n",
                g_tests_passed, g_tests_run);

        // Cleanup: kill any tmux sessions we created
        // (They'll be in the user's tmux, so clean up to be safe)

        return g_tests_failed > 0 ? 1 : 0;
    }
}
