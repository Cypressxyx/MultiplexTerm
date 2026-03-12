#import <Cocoa/Cocoa.h>
#include <stdint.h>
#include <string.h>

// === Bridge FFI ===
typedef struct {
    uint32_t ch;
    uint32_t fg;  // 0xFFFFFFFF = default, else 0x00RRGGBB
    uint32_t bg;
    uint8_t attrs;
    uint8_t _pad[3];
} BridgeCell;

extern uint8_t bridge_init(void);
extern void bridge_tick(void);
extern void bridge_key_input(const uint8_t* data, uint32_t len);
extern void bridge_resize(uint16_t cols, uint16_t rows);
extern uint16_t bridge_get_cols(void);
extern uint16_t bridge_get_rows(void);
extern uint16_t bridge_get_cursor_x(void);
extern uint16_t bridge_get_cursor_y(void);
extern uint8_t bridge_get_cursor_visible(void);
extern const BridgeCell* bridge_get_cells(void);
extern uint32_t bridge_get_cell_count(void);
extern uint16_t bridge_get_session_count(void);
extern const uint8_t* bridge_get_session_name(uint16_t idx);
extern uint16_t bridge_get_session_name_len(uint16_t idx);
extern uint8_t bridge_is_session_selected(uint16_t idx);
extern uint8_t bridge_is_session_attached(uint16_t idx);
extern uint8_t bridge_is_running(void);
extern uint8_t bridge_needs_redraw(void);
extern void bridge_clear_redraw(void);
extern uint8_t bridge_is_sidebar_visible(void);
extern void bridge_select_session(uint16_t idx);
extern void bridge_create_session(void);
extern void bridge_kill_session(uint16_t idx);
extern void bridge_rename_session(uint16_t idx, const uint8_t* name, uint16_t len);
extern void bridge_toggle_sidebar(void);
extern const uint8_t* bridge_get_session_display_name(uint16_t idx);
extern uint16_t bridge_get_session_display_name_len(uint16_t idx);
extern void bridge_tmux_command(uint8_t cmd_id);
extern uint8_t bridge_is_started(void);
extern void bridge_start_first_session(void);
extern uint16_t bridge_get_recent_project_count(void);
extern const uint8_t* bridge_get_recent_project_display(uint16_t idx);
extern uint16_t bridge_get_recent_project_display_len(uint16_t idx);
extern const uint8_t* bridge_get_recent_project_path(uint16_t idx);
extern uint16_t bridge_get_recent_project_path_len(uint16_t idx);
extern void bridge_create_session_in_dir(const uint8_t* path, uint16_t len);
extern void bridge_remove_recent_project(uint16_t idx);
// SSH remote hosts
extern uint16_t bridge_get_ssh_host_count(void);
extern const uint8_t* bridge_get_ssh_host_name(uint16_t idx);
extern uint16_t bridge_get_ssh_host_name_len(uint16_t idx);
extern uint8_t bridge_get_ssh_host_status(uint16_t idx);  // 0=disconnected, 1=connecting, 2=connected, 3=error
extern uint8_t bridge_get_ssh_host_expanded(uint16_t idx);
extern uint16_t bridge_get_ssh_session_count(uint16_t host_idx);
extern const uint8_t* bridge_get_ssh_session_name(uint16_t host_idx, uint16_t sess_idx);
extern uint16_t bridge_get_ssh_session_name_len(uint16_t host_idx, uint16_t sess_idx);
extern void bridge_toggle_ssh_host(uint16_t idx);
extern void bridge_select_ssh_session(uint16_t host_idx, uint16_t sess_idx);
extern void bridge_disconnect_ssh_host(uint16_t idx);
extern void bridge_refresh_ssh_hosts(void);
extern void bridge_create_ssh_shell(uint16_t host_idx);
extern void bridge_add_ssh_host(const uint8_t* name, uint16_t len);
extern void bridge_remove_ssh_host(uint16_t idx);
extern void bridge_kill_remote_session(uint16_t host_idx, uint16_t sess_idx);
extern void bridge_load_ssh_suggestions(void);
extern uint16_t bridge_get_ssh_suggestion_count(void);
extern const uint8_t* bridge_get_ssh_suggestion_name(uint16_t idx);
extern uint16_t bridge_get_ssh_suggestion_name_len(uint16_t idx);
extern uint8_t bridge_is_ssh_session(uint16_t idx);
extern uint16_t bridge_get_ssh_active_count(uint16_t host_idx);
extern uint16_t bridge_get_ssh_active_session_idx(uint16_t host_idx, uint16_t nth);
extern const uint8_t* bridge_get_ssh_active_display(uint16_t host_idx, uint16_t nth);
extern uint16_t bridge_get_ssh_active_display_len(uint16_t host_idx, uint16_t nth);

// === Layout constants ===
static const CGFloat kSidebarWidth    = 220.0;
static const CGFloat kSidebarPadH     = 16.0;
static const CGFloat kHeaderHeight    = 48.0;
static const CGFloat kSessionRowH     = 34.0;
static const CGFloat kNewBtnHeight    = 44.0;
static const CGFloat kAccentBarW      = 3.0;
static const CGFloat kTermPadLeft     = 4.0;
static const CGFloat kTitlebarInset   = 28.0; // space for traffic light buttons
static const CGFloat kRecentRowH      = 30.0;
static const CGFloat kRecentHeaderH   = 36.0;

// === Theme system ===
// Each theme defines 6 base colors; derived colors (textDim, selectedBg, etc.) are
// computed by blendHex() in applyTheme(). All UI drawing must use the g_* color
// globals — never hardcode hex values — so that themes work correctly everywhere.
typedef struct {
    const char* name;
    uint32_t bg;
    uint32_t fg;
    uint32_t sidebar;
    uint32_t border;
    uint32_t accent;
    uint32_t green;
} ThemeDef;

static const int kThemeCount = 25;
static const ThemeDef kThemes[] = {
    { "Vercel Dark",      0x0A0A0A, 0xEDEDED, 0x111111, 0x2A2A2A, 0xFAFAFA, 0x50E3C2 },
    { "Gruvbox Dark",     0x282828, 0xEBDBB2, 0x1D2021, 0x504945, 0xFABD2F, 0xB8BB26 },
    { "Gruvbox Light",    0xFBF1C7, 0x3C3836, 0xF2E5BC, 0xD5C4A1, 0xD65D0E, 0x98971A },
    { "Catppuccin Mocha", 0x1E1E2E, 0xCDD6F4, 0x181825, 0x313244, 0xCBA6F7, 0xA6E3A1 },
    { "Catppuccin Latte", 0xEFF1F5, 0x4C4F69, 0xE6E9EF, 0xCCD0DA, 0x8839EF, 0x40A02B },
    { "Kanagawa",         0x1F1F28, 0xDCD7BA, 0x16161D, 0x54546D, 0x7E9CD8, 0x76946A },
    { "Kanagawa Light",   0xF2ECBC, 0x1F1F28, 0xE7DBA0, 0xC8C093, 0x4E8CA2, 0x6F894E },
    { "Nord",             0x2E3440, 0xD8DEE9, 0x272C36, 0x3B4252, 0x88C0D0, 0xA3BE8C },
    { "Dracula",          0x282A36, 0xF8F8F2, 0x21222C, 0x44475A, 0xBD93F9, 0x50FA7B },
    { "One Dark",         0x282C34, 0xABB2BF, 0x21252B, 0x3E4451, 0x61AFEF, 0x98C379 },
    { "One Light",        0xFAFAFA, 0x383A42, 0xF0F0F0, 0xD0D0D0, 0x4078F2, 0x50A14F },
    { "Solarized Dark",   0x002B36, 0x839496, 0x00212B, 0x073642, 0x268BD2, 0x859900 },
    { "Solarized Light",  0xFDF6E3, 0x657B83, 0xEEE8D5, 0x93A1A1, 0x268BD2, 0x859900 },
    { "Tokyo Night",      0x1A1B26, 0xA9B1D6, 0x16161E, 0x3B4261, 0x7AA2F7, 0x9ECE6A },
    { "Tokyo Night Light",0xD5D6DB, 0x343B58, 0xCBCCD1, 0x9699A3, 0x34548A, 0x485E30 },
    { u8"Rosé Pine",      0x191724, 0xE0DEF4, 0x1F1D2E, 0x26233A, 0xC4A7E7, 0x9CCFD8 },
    { u8"Rosé Pine Dawn", 0xFAF4ED, 0x575279, 0xF2E9E1, 0xDFDAD9, 0x907AA9, 0x56949F },
    { "Everforest Dark",  0x2D353B, 0xD3C6AA, 0x272E33, 0x475258, 0xA7C080, 0xA7C080 },
    { "Everforest Light", 0xFDF6E3, 0x5C6A72, 0xF3EAD3, 0xD4C495, 0x8DA101, 0x8DA101 },
    { "Monokai Pro",      0x2D2A2E, 0xFCFCFA, 0x221F22, 0x403E41, 0xFFD866, 0xA9DC76 },
    { "Ayu Dark",         0x0A0E14, 0xB3B1AD, 0x07090D, 0x11151C, 0xE6B450, 0xAAD94C },
    { "Ayu Light",        0xFAFAFA, 0x575F66, 0xF0F0F0, 0xD8D8D8, 0xF2AE49, 0x86B300 },
    { "Nightfox",         0x192330, 0xCDCECF, 0x131A24, 0x2B3B51, 0x719CD6, 0x81B29A },
    { "Synthwave '84",    0x262335, 0xFFFFFF, 0x1E1A2E, 0x34294F, 0xFF7EDB, 0x72F1B8 },
    { "GitHub Dark",      0x0D1117, 0xC9D1D9, 0x010409, 0x21262D, 0x58A6FF, 0x3FB950 },
};

static int g_currentTheme = 0;  // Index into kThemes[] for the confirmed theme
static int g_savedTheme = 0;   // Snapshot before entering theme picker, for revert on cancel
static NSColor* g_bg;
static NSColor* g_sidebarBg;
static NSColor* g_border;
static NSColor* g_text;
static NSColor* g_textDim;
static NSColor* g_textMuted;
static NSColor* g_selectedBg;
static NSColor* g_hoverBg;
static NSColor* g_accent;
static NSColor* g_green;
static NSColor* g_cursor;
static NSColor* g_defaultFg;

static NSColor* hexColor(uint32_t hex) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:1.0];
}

// Compute a color between two hex values (blend towards `to` by `t` factor 0-1)
static uint32_t blendHex(uint32_t from, uint32_t to, float t) {
    int r = (int)(((from >> 16) & 0xFF) * (1-t) + ((to >> 16) & 0xFF) * t);
    int g = (int)(((from >> 8) & 0xFF) * (1-t) + ((to >> 8) & 0xFF) * t);
    int b = (int)((from & 0xFF) * (1-t) + (to & 0xFF) * t);
    return ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF);
}

static void applyTheme(int idx) {
    if (idx < 0 || idx >= kThemeCount) return;
    g_currentTheme = idx;
    const ThemeDef* t = &kThemes[idx];

    g_bg         = hexColor(t->bg);
    g_sidebarBg  = hexColor(t->sidebar);
    g_border     = hexColor(t->border);
    g_text       = hexColor(t->fg);
    g_textDim    = hexColor(blendHex(t->fg, t->bg, 0.45));
    g_textMuted  = hexColor(blendHex(t->fg, t->bg, 0.65));
    g_selectedBg = hexColor(blendHex(t->sidebar, t->fg, 0.07));
    g_hoverBg    = hexColor(blendHex(t->sidebar, t->fg, 0.04));
    g_accent     = hexColor(t->accent);
    g_green      = hexColor(t->green);
    g_cursor     = hexColor(t->accent);
    g_defaultFg  = hexColor(t->fg);
}

static void initTheme(void) {
    applyTheme(0); // Default: Vercel Dark
}

static NSColor* colorFromU32(uint32_t c, NSColor* def) {
    if (c == 0xFFFFFFFF) return def;
    return [NSColor colorWithSRGBRed:((c >> 16) & 0xFF) / 255.0
                               green:((c >> 8) & 0xFF) / 255.0
                                blue:(c & 0xFF) / 255.0
                               alpha:1.0];
}

// === Terminal View ===
@interface STTerminalView : NSView
@property (nonatomic, strong) NSFont* monoFont;
@property (nonatomic, strong) NSFont* boldFont;
@property (nonatomic, strong) NSFont* italicFont;
@property (nonatomic, strong) NSFont* boldItalicFont;
@property (nonatomic, strong) NSFont* uiFont;
@property (nonatomic, strong) NSFont* uiFontBold;
@property (nonatomic, strong) NSFont* uiFontSmall;
@property (nonatomic) CGFloat cellWidth;
@property (nonatomic) CGFloat cellHeight;
@property (nonatomic, strong) NSTimer* tickTimer;
@property (nonatomic) NSInteger hoveredSession; // -1 = none
@property (nonatomic) NSInteger hoveredRecentProject; // -1 = none
@property (nonatomic) NSInteger hoveredSshHost; // -1 = none
@property (nonatomic) NSInteger hoveredSshSession; // encoded: host_idx * 100 + sess_idx, -1 = none
@property (nonatomic) NSInteger closeArmedSession; // -1 = none (first click turns red, second click deletes)
@property (nonatomic) BOOL cursorBlink;
@property (nonatomic) NSUInteger blinkCounter;
@property (nonatomic, strong) NSTrackingArea* trackingArea;
// Text selection
@property (nonatomic) BOOL hasSelection;
@property (nonatomic) int selStartCol;
@property (nonatomic) int selStartRow;
@property (nonatomic) int selEndCol;
@property (nonatomic) int selEndRow;
@property (nonatomic) BOOL isDragging;
// Command palette (Cmd+K)
// paletteMode: 0 = commands list, 1 = theme picker (with live preview), 2 = add SSH host
// When entering theme mode, g_savedTheme is set so we can revert on cancel.
@property (nonatomic) BOOL paletteVisible;
@property (nonatomic) NSInteger paletteSelection;  // selected row (command idx or theme idx)
@property (nonatomic) NSInteger paletteMode;        // 0 = commands, 1 = themes, 2 = add SSH host
@property (nonatomic) NSInteger themeScroll;         // scroll offset for theme list (25 themes, 12 visible)
@property (nonatomic, strong) NSMutableString* paletteSearchText;
@end

static const int kPaletteItemCount = 9; // 8 commands + 1 theme
static NSString* const kPaletteLabels[] = {
    @"Split Pane Right",
    @"Split Pane Down",
    @"New Window",
    @"Next Window",
    @"Previous Window",
    @"Next Pane",
    @"Close Pane",
    @"Toggle Zoom",
    @"Theme...",
};
static NSString* const kPaletteHints[] = {
    @"\u2502",  // │
    @"\u2500",  // ─
    @"+",
    @"\u2192",  // →
    @"\u2190",  // ←
    @"\u21BB",  // ↻
    @"\u00D7",  // ×
    @"\u2922",  // ⤢
    @"\u25CF",  // ●
};

@implementation STTerminalView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        CGFloat termFontSize = 14.0;
        self.monoFont = [NSFont monospacedSystemFontOfSize:termFontSize weight:NSFontWeightRegular];
        self.boldFont = [NSFont monospacedSystemFontOfSize:termFontSize weight:NSFontWeightBold];
        self.italicFont = [NSFont fontWithName:@"Menlo-Italic" size:termFontSize];
        if (!self.italicFont) self.italicFont = self.monoFont;
        self.boldItalicFont = [NSFont fontWithName:@"Menlo-BoldItalic" size:termFontSize];
        if (!self.boldItalicFont) self.boldItalicFont = self.boldFont;

        self.uiFont = [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
        self.uiFontBold = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
        self.uiFontSmall = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];

        NSDictionary* attrs = @{NSFontAttributeName: self.monoFont};
        CGSize sz = [@"M" sizeWithAttributes:attrs];
        self.cellWidth = ceil(sz.width);
        self.cellHeight = ceil(self.monoFont.ascender - self.monoFont.descender + self.monoFont.leading);
        if (self.cellHeight < 1) self.cellHeight = ceil(sz.height);

        self.hoveredSession = -1;
        self.hoveredRecentProject = -1;
        self.hoveredSshHost = -1;
        self.hoveredSshSession = -1;
        self.closeArmedSession = -1;
        self.cursorBlink = YES;
        self.blinkCounter = 0;
        self.hasSelection = NO;
        self.isDragging = NO;
        self.paletteVisible = NO;
        self.paletteSelection = 0;
        self.paletteMode = 0;
        self.themeScroll = 0;
        self.paletteSearchText = [NSMutableString string];

        // Register for file drag-and-drop
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)canBecomeKeyView { return YES; }

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) [self removeTrackingArea:self.trackingArea];
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
        options:(NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect)
        owner:self userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (CGFloat)sidebarPx {
    if (!bridge_is_sidebar_visible()) return 0;
    return kSidebarWidth;
}

- (void)recalcTermSize {
    NSSize size = self.bounds.size;
    CGFloat sbw = [self sidebarPx];
    CGFloat termAreaW = size.width - sbw - kTermPadLeft;
    CGFloat termAreaH = size.height - kTitlebarInset;
    uint16_t cols = (uint16_t)(termAreaW / self.cellWidth);
    uint16_t rows = (uint16_t)(termAreaH / self.cellHeight);
    if (cols > 0 && rows > 0) bridge_resize(cols, rows);
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self recalcTermSize];
}

- (void)tick:(NSTimer*)timer {
    bridge_tick();

    self.blinkCounter++;
    if (self.blinkCounter % 30 == 0) {
        self.cursorBlink = !self.cursorBlink;
        bridge_clear_redraw();
        [self setNeedsDisplay:YES];
    }

    if (bridge_needs_redraw()) {
        bridge_clear_redraw();
        [self setNeedsDisplay:YES];
    }
    if (!bridge_is_running()) {
        [timer invalidate];
        self.tickTimer = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSApp terminate:nil];
        });
    }
}

// === Drawing ===
// Draw order: bg → terminal cells → cursor → sidebar → palette card.
// Palette floats on top with drop shadow (no overlay — see pitfalls in AGENTS.md).
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    @autoreleasepool {
        [g_bg setFill];
        NSRectFill(self.bounds);
        if (bridge_is_started()) {
            [self drawTerminal];
            if (bridge_get_cursor_visible() && self.cursorBlink) [self drawCursor];
        } else {
            [self drawEmptyState];
        }
        if (bridge_is_sidebar_visible()) [self drawSidebar];
        if (self.paletteVisible) [self drawPalette];
    }
}

- (void)drawSidebar {
    CGFloat h = self.bounds.size.height;
    CGFloat sw = kSidebarWidth;

    // Truncating paragraph style for sidebar text
    NSMutableParagraphStyle* truncStyle = [[NSMutableParagraphStyle alloc] init];
    truncStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    // Sidebar background
    [g_sidebarBg setFill];
    NSRectFill(NSMakeRect(0, 0, sw, h));

    // Right border
    [g_border setFill];
    NSRectFill(NSMakeRect(sw - 1, 0, 1, h));

    // Titlebar inset (space for traffic light buttons)
    CGFloat top = kTitlebarInset;

    // Header: "SESSIONS"
    NSDictionary* headerAttrs = @{
        NSFontAttributeName: self.uiFontSmall,
        NSForegroundColorAttributeName: g_textMuted,
        NSKernAttributeName: @1.5,
    };
    [@"SESSIONS" drawAtPoint:NSMakePoint(kSidebarPadH, top + 10) withAttributes:headerAttrs];

    // Header bottom border
    CGFloat headerBottom = top + kHeaderHeight;
    [g_border setFill];
    NSRectFill(NSMakeRect(0, headerBottom - 1, sw, 1));

    // Session list
    uint16_t count = bridge_get_session_count();
    CGFloat y = headerBottom;

    for (uint16_t i = 0; i < count; i++) {
        // Skip SSH sessions — they show under REMOTE
        if (bridge_is_ssh_session(i)) continue;

        uint8_t sel = bridge_is_session_selected(i);
        uint8_t att = bridge_is_session_attached(i);
        NSRect rowRect = NSMakeRect(0, y, sw - 1, kSessionRowH);

        // Row background
        if (sel) {
            [g_selectedBg setFill];
            NSRectFill(rowRect);
            // Left accent bar
            [g_accent setFill];
            NSRectFill(NSMakeRect(0, y + 4, kAccentBarW, kSessionRowH - 8));
        } else if (self.hoveredSession == i) {
            [g_hoverBg setFill];
            NSRectFill(rowRect);
        }

        // Attached indicator (green dot) — space always reserved
        CGFloat dotX = kSidebarPadH;
        CGFloat dotY = y + (kSessionRowH - 6) / 2;
        if (att) {
            NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, dotY, 6, 6)];
            [g_green setFill];
            [dot fill];
        }

        // Session display name — always indented past dot area
        uint16_t nameLen = bridge_get_session_display_name_len(i);
        const uint8_t* namePtr = bridge_get_session_display_name(i);
        NSString* name = [[NSString alloc] initWithBytes:namePtr length:nameLen encoding:NSUTF8StringEncoding];
        if (!name) name = @"?";

        CGFloat textX = kSidebarPadH + 14; // always reserve dot space
        CGFloat textY = y + (kSessionRowH - 16) / 2;

        NSDictionary* nameAttrs = @{
            NSFontAttributeName: sel ? self.uiFontBold : self.uiFont,
            NSForegroundColorAttributeName: sel ? g_text : g_textDim,
            NSParagraphStyleAttributeName: truncStyle,
        };
        [name drawInRect:NSMakeRect(textX, textY, sw - 28 - textX, kSessionRowH) withAttributes:nameAttrs];

        // Close "×" button (visible on hover or selected)
        if (sel || self.hoveredSession == i) {
            BOOL armed = (self.closeArmedSession == i);
            NSColor* closeColor = armed ? hexColor(0xFF4444) : g_textMuted;
            NSDictionary* closeAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:14 weight:armed ? NSFontWeightMedium : NSFontWeightLight],
                NSForegroundColorAttributeName: closeColor,
            };
            CGFloat closeX = sw - 28;
            CGFloat closeY = y + (kSessionRowH - 16) / 2;
            [@"\u00D7" drawAtPoint:NSMakePoint(closeX, closeY) withAttributes:closeAttrs];
        }

        y += kSessionRowH;
        if (y + kSessionRowH > h) break;
    }

    // "+ New Session" button (after sessions, not bottom-anchored)
    CGFloat btnY = y;
    [g_border setFill];
    NSRectFill(NSMakeRect(0, btnY, sw, 1));

    NSDictionary* btnAttrs = @{
        NSFontAttributeName: self.uiFont,
        NSForegroundColorAttributeName: g_textMuted,
    };
    NSString* btnText = @"+ New Session";
    CGSize btnSz = [btnText sizeWithAttributes:btnAttrs];
    CGFloat btnTextX = kSidebarPadH + 14;
    CGFloat btnTextY = btnY + (kNewBtnHeight - btnSz.height) / 2;
    [btnText drawAtPoint:NSMakePoint(btnTextX, btnTextY) withAttributes:btnAttrs];
    y = btnY + kNewBtnHeight;

    // SSH Remote section (always shown)
    uint16_t sshCount = bridge_get_ssh_host_count();
    {
        [g_border setFill];
        NSRectFill(NSMakeRect(0, y, sw, 1));
        [@"REMOTE" drawAtPoint:NSMakePoint(kSidebarPadH, y + 8) withAttributes:headerAttrs];
        y += kRecentHeaderH;

        for (uint16_t hi = 0; hi < sshCount; hi++) {
            if (y + kSessionRowH > h) break;
            uint8_t status = bridge_get_ssh_host_status(hi);
            uint8_t expanded = bridge_get_ssh_host_expanded(hi);

            // Host row
            NSRect hostRect = NSMakeRect(0, y, sw - 1, kSessionRowH);
            if (self.hoveredSshHost == hi) {
                [g_hoverBg setFill];
                NSRectFill(hostRect);
            }

            // Status indicator
            CGFloat dotX = kSidebarPadH;
            CGFloat dotY = y + (kSessionRowH - 6) / 2;
            NSColor* dotColor;
            switch (status) {
                case 2: dotColor = g_green; break;       // connected
                case 1: dotColor = g_accent; break;      // connecting
                case 3: dotColor = hexColor(0xFF4444); break;  // error
                default: dotColor = g_textMuted; break;  // disconnected
            }
            NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, dotY, 6, 6)];
            [dotColor setFill];
            [dot fill];
            if (status == 0) {
                // Hollow dot for disconnected
                [g_sidebarBg setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX + 1.5, dotY + 1.5, 3, 3)] fill];
            }

            // Expand arrow for connected hosts
            if (status == 2) {
                NSString* arrow = expanded ? @"\u25BE" : @"\u25B8"; // ▾ or ▸
                NSDictionary* arrowAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: g_textMuted,
                };
                [arrow drawAtPoint:NSMakePoint(sw - 24, y + (kSessionRowH - 12) / 2) withAttributes:arrowAttrs];
            }

            // Spinner-like indicator for connecting
            if (status == 1) {
                NSDictionary* spinAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: g_accent,
                };
                [@"\u21BB" drawAtPoint:NSMakePoint(sw - 24, y + (kSessionRowH - 12) / 2) withAttributes:spinAttrs]; // ↻
            }

            // Host name
            uint16_t nameLen = bridge_get_ssh_host_name_len(hi);
            const uint8_t* namePtr = bridge_get_ssh_host_name(hi);
            NSString* hostName = [[NSString alloc] initWithBytes:namePtr length:nameLen encoding:NSUTF8StringEncoding];
            if (!hostName) hostName = @"?";

            NSDictionary* hostNameAttrs = @{
                NSFontAttributeName: self.uiFont,
                NSForegroundColorAttributeName: status == 2 ? g_text : g_textDim,
                NSParagraphStyleAttributeName: truncStyle,
            };
            CGFloat hnTextX = kSidebarPadH + 14;
            [hostName drawInRect:NSMakeRect(hnTextX, y + (kSessionRowH - 16) / 2, sw - 28 - hnTextX, kSessionRowH) withAttributes:hostNameAttrs];

            // × remove button on hover
            if (self.hoveredSshHost == hi) {
                NSDictionary* closeAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightLight],
                    NSForegroundColorAttributeName: g_textMuted,
                };
                [@"\u00D7" drawAtPoint:NSMakePoint(sw - 28, y + (kSessionRowH - 16) / 2) withAttributes:closeAttrs];
            }

            y += kSessionRowH;

            // Draw remote sessions if expanded
            if (expanded && status == 2) {
                // Active local SSH sessions for this host
                uint16_t activeCount = bridge_get_ssh_active_count(hi);
                for (uint16_t ai = 0; ai < activeCount; ai++) {
                    if (y + kRecentRowH > h) break;

                    uint16_t sessIdx = bridge_get_ssh_active_session_idx(hi, ai);
                    uint8_t isSel = (sessIdx != 0xFFFF) ? bridge_is_session_selected(sessIdx) : 0;

                    NSRect sessRect = NSMakeRect(0, y, sw - 1, kRecentRowH);
                    // Encode active sessions with offset: hi * 100 + 50 + ai
                    NSInteger encodedActive = hi * 100 + 50 + ai;
                    if (isSel) {
                        [g_selectedBg setFill];
                        NSRectFill(sessRect);
                        [g_accent setFill];
                        NSRectFill(NSMakeRect(0, y + 3, kAccentBarW, kRecentRowH - 6));
                    } else if (self.hoveredSshSession == encodedActive) {
                        [g_hoverBg setFill];
                        NSRectFill(sessRect);
                    }

                    // Green dot for active
                    NSBezierPath* activeDot = [NSBezierPath bezierPathWithOvalInRect:
                        NSMakeRect(kSidebarPadH + 14, y + (kRecentRowH - 5) / 2, 5, 5)];
                    [g_green setFill];
                    [activeDot fill];

                    uint16_t dLen = bridge_get_ssh_active_display_len(hi, ai);
                    const uint8_t* dPtr = bridge_get_ssh_active_display(hi, ai);
                    NSString* dName = [[NSString alloc] initWithBytes:dPtr length:dLen encoding:NSUTF8StringEncoding];
                    if (!dName) dName = @"?";

                    NSDictionary* activeAttrs = @{
                        NSFontAttributeName: isSel ? self.uiFontBold : self.uiFont,
                        NSForegroundColorAttributeName: isSel ? g_text : g_textDim,
                        NSParagraphStyleAttributeName: truncStyle,
                    };
                    CGFloat aTextX = kSidebarPadH + 26;
                    [dName drawInRect:NSMakeRect(aTextX, y + (kRecentRowH - 14) / 2, sw - 28 - aTextX, kRecentRowH) withAttributes:activeAttrs];

                    // × close button on hover or selected
                    if (isSel || self.hoveredSshSession == encodedActive) {
                        NSDictionary* closeAttrs = @{
                            NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightLight],
                            NSForegroundColorAttributeName: g_textMuted,
                        };
                        [@"\u00D7" drawAtPoint:NSMakePoint(sw - 28, y + (kRecentRowH - 16) / 2) withAttributes:closeAttrs];
                    }
                    y += kRecentRowH;
                }

                // Remote tmux sessions (from SSH probe)
                uint16_t sessCount = bridge_get_ssh_session_count(hi);
                for (uint16_t si = 0; si < sessCount; si++) {
                    if (y + kRecentRowH > h) break;

                    NSRect sessRect = NSMakeRect(0, y, sw - 1, kRecentRowH);
                    NSInteger encodedSess = hi * 100 + si;
                    if (self.hoveredSshSession == encodedSess) {
                        [g_hoverBg setFill];
                        NSRectFill(sessRect);
                    }

                    uint16_t sNameLen = bridge_get_ssh_session_name_len(hi, si);
                    const uint8_t* sNamePtr = bridge_get_ssh_session_name(hi, si);
                    NSString* sessName = [[NSString alloc] initWithBytes:sNamePtr length:sNameLen encoding:NSUTF8StringEncoding];
                    if (!sessName) sessName = @"?";

                    NSDictionary* sessAttrs = @{
                        NSFontAttributeName: self.uiFont,
                        NSForegroundColorAttributeName: g_textMuted,
                        NSParagraphStyleAttributeName: truncStyle,
                    };
                    // Indented under host — dimmer since not yet connected
                    CGFloat sTextX = kSidebarPadH + 26;
                    [sessName drawInRect:NSMakeRect(sTextX, y + (kRecentRowH - 14) / 2, sw - 28 - sTextX, kRecentRowH) withAttributes:sessAttrs];

                    // × close button on hover
                    if (self.hoveredSshSession == encodedSess) {
                        NSDictionary* closeAttrs = @{
                            NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightLight],
                            NSForegroundColorAttributeName: g_textMuted,
                        };
                        [@"\u00D7" drawAtPoint:NSMakePoint(sw - 28, y + (kRecentRowH - 16) / 2) withAttributes:closeAttrs];
                    }
                    y += kRecentRowH;
                }

                // "No sessions" hint if nothing at all
                if (activeCount == 0 && sessCount == 0) {
                    NSDictionary* emptyAttrs = @{
                        NSFontAttributeName: self.uiFont,
                        NSForegroundColorAttributeName: g_textMuted,
                    };
                    [@"  No sessions" drawAtPoint:NSMakePoint(kSidebarPadH + 14, y + (kRecentRowH - 14) / 2) withAttributes:emptyAttrs];
                    y += kRecentRowH;
                }

                // "+ New Session" row
                if (y + kRecentRowH <= h) {
                    NSDictionary* newSessAttrs = @{
                        NSFontAttributeName: self.uiFont,
                        NSForegroundColorAttributeName: g_textMuted,
                    };
                    [@"  + New Session" drawAtPoint:NSMakePoint(kSidebarPadH + 14, y + (kRecentRowH - 14) / 2) withAttributes:newSessAttrs];
                    y += kRecentRowH;
                }
            }
        }

        // "+ Add Host" button
        [g_border setFill];
        NSRectFill(NSMakeRect(0, y, sw, 1));
        CGFloat addHostBtnY = y;
        NSString* addHostText = @"+ Add Host";
        CGSize addHostSz = [addHostText sizeWithAttributes:btnAttrs];
        CGFloat addHostTextX = kSidebarPadH + 14;
        CGFloat addHostTextY = y + (kNewBtnHeight * 0.7 - addHostSz.height) / 2;
        [addHostText drawAtPoint:NSMakePoint(addHostTextX, addHostTextY) withAttributes:btnAttrs];
        y += kNewBtnHeight * 0.7;
    }

    // Recent Projects section (always shown)
    uint16_t rpCount = bridge_get_recent_project_count();
    [g_border setFill];
    NSRectFill(NSMakeRect(0, y, sw, 1));
    [@"RECENT PROJECTS" drawAtPoint:NSMakePoint(kSidebarPadH, y + 8) withAttributes:headerAttrs];
    y += kRecentHeaderH;

    if (rpCount == 0) {
        NSDictionary* emptyAttrs = @{
            NSFontAttributeName: self.uiFont,
            NSForegroundColorAttributeName: g_textMuted,
        };
        [@"Nothing yet" drawAtPoint:NSMakePoint(kSidebarPadH + 14, y + (kRecentRowH - 14) / 2) withAttributes:emptyAttrs];
        y += kRecentRowH;
    } else {
        for (uint16_t i = 0; i < rpCount; i++) {
            if (y + kRecentRowH > h) break;

            NSRect rowRect = NSMakeRect(0, y, sw - 1, kRecentRowH);
            if (self.hoveredRecentProject == i) {
                [g_hoverBg setFill];
                NSRectFill(rowRect);
            }

            uint16_t dLen = bridge_get_recent_project_display_len(i);
            const uint8_t* dPtr = bridge_get_recent_project_display(i);
            NSString* dName = [[NSString alloc] initWithBytes:dPtr length:dLen encoding:NSUTF8StringEncoding];
            if (!dName) dName = @"?";

            NSDictionary* rpAttrs = @{
                NSFontAttributeName: self.uiFont,
                NSForegroundColorAttributeName: g_textDim,
                NSParagraphStyleAttributeName: truncStyle,
            };
            CGFloat rpTextX = kSidebarPadH + 14;
            CGFloat rpTextY = y + (kRecentRowH - 14) / 2;
            [dName drawInRect:NSMakeRect(rpTextX, rpTextY, sw - 28 - rpTextX, kRecentRowH) withAttributes:rpAttrs];

            // Close × on hover
            if (self.hoveredRecentProject == i) {
                NSDictionary* closeAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightLight],
                    NSForegroundColorAttributeName: g_textMuted,
                };
                [@"\u00D7" drawAtPoint:NSMakePoint(sw - 26, rpTextY) withAttributes:closeAttrs];
            }

            y += kRecentRowH;
        }
    }
}

- (int)getFilteredCommandIndices:(int*)outIndices {
    int count = 0;
    if (self.paletteSearchText.length == 0) {
        for (int i = 0; i < kPaletteItemCount; i++) outIndices[count++] = i;
    } else {
        NSString* query = [self.paletteSearchText lowercaseString];
        for (int i = 0; i < kPaletteItemCount; i++) {
            if ([[kPaletteLabels[i] lowercaseString] containsString:query]) {
                outIndices[count++] = i;
            }
        }
    }
    return count;
}

- (int)getFilteredThemeIndices:(int*)outIndices {
    int count = 0;
    if (self.paletteSearchText.length == 0) {
        for (int i = 0; i < kThemeCount; i++) outIndices[count++] = i;
    } else {
        NSString* query = [self.paletteSearchText lowercaseString];
        for (int i = 0; i < kThemeCount; i++) {
            NSString* name = [[NSString stringWithUTF8String:kThemes[i].name] lowercaseString];
            if ([name containsString:query]) {
                outIndices[count++] = i;
            }
        }
    }
    return count;
}

- (int)getFilteredSshSuggestionIndices:(int*)outIndices {
    uint16_t total = bridge_get_ssh_suggestion_count();
    int count = 0;
    if (self.paletteSearchText.length == 0) {
        for (int i = 0; i < total && count < 32; i++) outIndices[count++] = i;
    } else {
        NSString* query = [self.paletteSearchText lowercaseString];
        for (int i = 0; i < total && count < 32; i++) {
            uint16_t nLen = bridge_get_ssh_suggestion_name_len(i);
            const uint8_t* nPtr = bridge_get_ssh_suggestion_name(i);
            NSString* name = [[NSString alloc] initWithBytes:nPtr length:nLen encoding:NSUTF8StringEncoding];
            if (!name) continue;
            if ([[name lowercaseString] containsString:query]) {
                outIndices[count++] = i;
            }
        }
    }
    return count;
}

- (void)drawPaletteSearchBar:(CGFloat)cardX y:(CGFloat)cardY w:(CGFloat)cardW placeholder:(NSString*)placeholder leftInset:(CGFloat)leftInset {
    CGFloat inputMargin = leftInset;
    CGFloat inputH = 28;
    CGFloat inputX = cardX + inputMargin;
    CGFloat inputY = cardY + 8;
    CGFloat inputW = cardW - inputMargin - 14;

    NSBezierPath* inputPath = [NSBezierPath bezierPathWithRoundedRect:
        NSMakeRect(inputX, inputY, inputW, inputH) xRadius:6 yRadius:6];
    [g_bg setFill];
    [inputPath fill];
    [g_border setStroke];
    inputPath.lineWidth = 0.5;
    [inputPath stroke];

    NSDictionary* searchFontAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
    };
    NSString* searchDisplay = self.paletteSearchText.length > 0
        ? [self.paletteSearchText copy] : placeholder;
    NSColor* searchColor = self.paletteSearchText.length > 0 ? g_text : g_textMuted;
    NSDictionary* searchAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: searchColor,
    };
    [searchDisplay drawAtPoint:NSMakePoint(inputX + 10, inputY + 5) withAttributes:searchAttrs];

    // Cursor bar
    CGFloat cursorTextW = self.paletteSearchText.length > 0
        ? [self.paletteSearchText sizeWithAttributes:searchFontAttrs].width : 0;
    [g_accent setFill];
    NSRectFill(NSMakeRect(inputX + 10 + cursorTextW, inputY + 6, 1.5, inputH - 12));
}

- (void)drawAddHostInput {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    int filteredIndices[32];
    int filteredCount = [self getFilteredSshSuggestionIndices:filteredIndices];

    CGFloat cardW = 360;
    CGFloat headerH = 44;
    CGFloat rowH = 34;
    CGFloat hintH = 28;
    // Show suggestion list if there are suggestions, otherwise just the hint
    int displayRows = filteredCount > 0 ? filteredCount : 0;
    CGFloat listH = displayRows * rowH;
    CGFloat cardH = headerH + listH + hintH + 12;
    CGFloat cardX = (w - cardW) / 2;
    CGFloat cardY = h * 0.2;

    // Shadow
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.6];
    shadow.shadowOffset = NSMakeSize(0, -4);
    shadow.shadowBlurRadius = 24;

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    NSBezierPath* cardPath = [NSBezierPath bezierPathWithRoundedRect:
        NSMakeRect(cardX, cardY, cardW, cardH) xRadius:12 yRadius:12];
    [g_sidebarBg setFill];
    [cardPath fill];
    [NSGraphicsContext restoreGraphicsState];

    [g_border setStroke];
    cardPath.lineWidth = 1;
    [cardPath stroke];

    // Search bar as input field
    [self drawPaletteSearchBar:cardX y:cardY w:cardW placeholder:@"user@hostname or ssh config host" leftInset:14];

    [g_border setFill];
    NSRectFill(NSMakeRect(cardX, cardY + headerH, cardW, 1));

    // Suggestion list from ~/.ssh/config
    if (filteredCount > 0) {
        CGFloat itemY = cardY + headerH + 4;
        for (int fi = 0; fi < filteredCount; fi++) {
            int i = filteredIndices[fi];
            BOOL sel = (self.paletteSelection == fi);

            if (sel) {
                NSBezierPath* rowBg = [NSBezierPath bezierPathWithRoundedRect:
                    NSMakeRect(cardX + 6, itemY, cardW - 12, rowH) xRadius:6 yRadius:6];
                [g_selectedBg setFill];
                [rowBg fill];
            }

            uint16_t nLen = bridge_get_ssh_suggestion_name_len(i);
            const uint8_t* nPtr = bridge_get_ssh_suggestion_name(i);
            NSString* name = [[NSString alloc] initWithBytes:nPtr length:nLen encoding:NSUTF8StringEncoding];
            if (!name) name = @"?";

            NSDictionary* nameAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:13 weight:sel ? NSFontWeightMedium : NSFontWeightRegular],
                NSForegroundColorAttributeName: sel ? g_text : g_textDim,
            };
            [name drawAtPoint:NSMakePoint(cardX + 20, itemY + 8) withAttributes:nameAttrs];

            // "from ssh config" label
            NSDictionary* srcAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightRegular],
                NSForegroundColorAttributeName: g_textMuted,
            };
            [@"ssh config" drawAtPoint:NSMakePoint(cardX + cardW - 80, itemY + 10) withAttributes:srcAttrs];

            itemY += rowH;
        }
    }

    // Hint text at bottom
    NSDictionary* hintAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: g_textMuted,
    };
    CGFloat hintY = cardY + headerH + listH + 8;
    [@"Enter to add \u00B7 Escape to cancel" drawAtPoint:NSMakePoint(cardX + 14, hintY) withAttributes:hintAttrs];
}

- (void)drawPalette {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // IMPORTANT: No full-screen overlay here. A semi-transparent overlay makes
    // terminal content invisible on dark themes. The card uses a drop shadow instead.

    if (self.paletteMode == 1) {
        [self drawThemePicker];
        return;
    }
    if (self.paletteMode == 2) {
        [self drawAddHostInput];
        return;
    }

    // Compute filtered items
    int filteredIndices[9];
    int filteredCount = [self getFilteredCommandIndices:filteredIndices];

    // Palette card
    CGFloat cardW = 320;
    CGFloat rowH = 38;
    CGFloat headerH = 44;
    int displayCount = filteredCount > 0 ? filteredCount : 1;
    CGFloat cardH = headerH + rowH * displayCount + 8;
    CGFloat cardX = (w - cardW) / 2;
    CGFloat cardY = h * 0.2;

    // Shadow behind card
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.6];
    shadow.shadowOffset = NSMakeSize(0, -4);
    shadow.shadowBlurRadius = 24;

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    NSBezierPath* cardPath = [NSBezierPath bezierPathWithRoundedRect:
        NSMakeRect(cardX, cardY, cardW, cardH) xRadius:12 yRadius:12];
    [g_sidebarBg setFill];
    [cardPath fill];
    [NSGraphicsContext restoreGraphicsState];

    [g_border setStroke];
    cardPath.lineWidth = 1;
    [cardPath stroke];

    // Search bar in header
    [self drawPaletteSearchBar:cardX y:cardY w:cardW placeholder:@"Search commands..." leftInset:14];

    [g_border setFill];
    NSRectFill(NSMakeRect(cardX, cardY + headerH, cardW, 1));

    if (filteredCount == 0) {
        NSDictionary* noResultAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: g_textMuted,
        };
        [@"No results" drawAtPoint:NSMakePoint(cardX + 20, cardY + headerH + 12) withAttributes:noResultAttrs];
    } else {
        CGFloat itemY = cardY + headerH + 4;
        for (int fi = 0; fi < filteredCount; fi++) {
            int i = filteredIndices[fi];
            BOOL sel = (self.paletteSelection == fi);

            if (sel) {
                NSBezierPath* rowBg = [NSBezierPath bezierPathWithRoundedRect:
                    NSMakeRect(cardX + 6, itemY, cardW - 12, rowH) xRadius:6 yRadius:6];
                [g_selectedBg setFill];
                [rowBg fill];
            }

            NSDictionary* hintAttrs = @{
                NSFontAttributeName: [NSFont monospacedSystemFontOfSize:15 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: sel ? g_green : g_textMuted,
            };
            [kPaletteHints[i] drawAtPoint:NSMakePoint(cardX + 20, itemY + 9) withAttributes:hintAttrs];

            NSDictionary* labelAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:13 weight:sel ? NSFontWeightMedium : NSFontWeightRegular],
                NSForegroundColorAttributeName: sel ? g_text : g_textDim,
            };
            [kPaletteLabels[i] drawAtPoint:NSMakePoint(cardX + 48, itemY + 10) withAttributes:labelAttrs];

            // Arrow indicator for submenu items
            if (i == kPaletteItemCount - 1) {
                NSDictionary* arrowAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightRegular],
                    NSForegroundColorAttributeName: sel ? g_text : g_textMuted,
                };
                [@"\u203A" drawAtPoint:NSMakePoint(cardX + cardW - 28, itemY + 10) withAttributes:arrowAttrs];
            }

            itemY += rowH;
        }
    }
}

- (void)drawThemePicker {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Compute filtered themes
    int filteredIndices[25];
    int filteredCount = [self getFilteredThemeIndices:filteredIndices];

    CGFloat cardW = 340;
    CGFloat rowH = 34;
    CGFloat headerH = 44;
    int maxVisible = 12;
    int displayCount = filteredCount > 0 ? (filteredCount < maxVisible ? filteredCount : maxVisible) : 1;
    CGFloat cardH = headerH + rowH * displayCount + 8;
    CGFloat cardX = (w - cardW) / 2;
    CGFloat cardY = h * 0.15;

    // Shadow behind card
    NSShadow* shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.6];
    shadow.shadowOffset = NSMakeSize(0, -4);
    shadow.shadowBlurRadius = 24;

    [NSGraphicsContext saveGraphicsState];
    [shadow set];
    NSBezierPath* cardPath = [NSBezierPath bezierPathWithRoundedRect:
        NSMakeRect(cardX, cardY, cardW, cardH) xRadius:12 yRadius:12];
    [g_sidebarBg setFill];
    [cardPath fill];
    [NSGraphicsContext restoreGraphicsState];

    [g_border setStroke];
    cardPath.lineWidth = 1;
    [cardPath stroke];

    // Header: back button + search field
    NSDictionary* backAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:16 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: g_textMuted,
    };
    [@"\u2039" drawAtPoint:NSMakePoint(cardX + 14, cardY + 12) withAttributes:backAttrs];

    [self drawPaletteSearchBar:cardX y:cardY w:cardW placeholder:@"Search themes..." leftInset:34];

    [g_border setFill];
    NSRectFill(NSMakeRect(cardX, cardY + headerH, cardW, 1));

    if (filteredCount == 0) {
        NSDictionary* noResultAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: g_textMuted,
        };
        [@"No results" drawAtPoint:NSMakePoint(cardX + 20, cardY + headerH + 12) withAttributes:noResultAttrs];
    } else {
        // Theme list
        CGFloat itemY = cardY + headerH + 4;
        int visibleItems = filteredCount < maxVisible ? filteredCount : maxVisible;
        for (int vi = 0; vi < visibleItems && (vi + self.themeScroll) < filteredCount; vi++) {
            int filteredIdx = (int)(vi + self.themeScroll);
            int themeIdx = filteredIndices[filteredIdx];
            BOOL sel = (self.paletteSelection == filteredIdx);
            BOOL current = (themeIdx == g_savedTheme);

            if (sel) {
                NSBezierPath* rowBg = [NSBezierPath bezierPathWithRoundedRect:
                    NSMakeRect(cardX + 6, itemY, cardW - 12, rowH) xRadius:6 yRadius:6];
                [g_selectedBg setFill];
                [rowBg fill];
            }

            // Color preview swatch
            const ThemeDef* td = &kThemes[themeIdx];
            CGFloat swatchY = itemY + (rowH - 14) / 2;
            NSBezierPath* swatch = [NSBezierPath bezierPathWithRoundedRect:
                NSMakeRect(cardX + 18, swatchY, 14, 14) xRadius:3 yRadius:3];
            [hexColor(td->bg) setFill];
            [swatch fill];
            [hexColor(td->border) setStroke];
            swatch.lineWidth = 1;
            [swatch stroke];

            // Accent dot inside swatch
            NSBezierPath* accentDot = [NSBezierPath bezierPathWithOvalInRect:
                NSMakeRect(cardX + 22, swatchY + 4, 6, 6)];
            [hexColor(td->accent) setFill];
            [accentDot fill];

            // Theme name
            NSString* name = [NSString stringWithUTF8String:td->name];
            NSDictionary* labelAttrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:13 weight:sel ? NSFontWeightMedium : NSFontWeightRegular],
                NSForegroundColorAttributeName: sel ? g_text : g_textDim,
            };
            [name drawAtPoint:NSMakePoint(cardX + 42, itemY + 8) withAttributes:labelAttrs];

            // Checkmark for current theme
            if (current) {
                NSDictionary* checkAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: g_green,
                };
                [@"\u2713" drawAtPoint:NSMakePoint(cardX + cardW - 30, itemY + 8) withAttributes:checkAttrs];
            }

            itemY += rowH;
        }
    }
}

- (CGFloat)emptyStateSshSectionHeight {
    uint16_t sshCount = bridge_get_ssh_host_count();
    CGFloat sshH = 24; // REMOTE header
    for (uint16_t hi = 0; hi < sshCount; hi++) {
        sshH += 30; // host row
        uint8_t status = bridge_get_ssh_host_status(hi);
        uint8_t expanded = bridge_get_ssh_host_expanded(hi);
        if (expanded && status == 2) {
            uint16_t activeCount = bridge_get_ssh_active_count(hi);
            uint16_t sessCount = bridge_get_ssh_session_count(hi);
            sshH += activeCount * 28;
            sshH += sessCount * 28;
            if (activeCount == 0 && sessCount == 0) sshH += 28; // "No sessions"
            sshH += 28; // "+ New Session"
        }
    }
    sshH += 28; // "+ Add Host"
    return sshH;
}

- (void)drawEmptyState {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;
    CGFloat sbw = [self sidebarPx];
    CGFloat areaX = sbw;
    CGFloat areaW = w - sbw;
    CGFloat centerX = areaX + areaW / 2;

    uint16_t rpCount = bridge_get_recent_project_count();
    uint16_t sshCount = bridge_get_ssh_host_count();
    CGFloat rpRows = rpCount > 0 ? rpCount : 1;
    CGFloat sshSectionH = [self emptyStateSshSectionHeight];
    CGFloat totalH = 40 + 30 + sshSectionH + 20 + 24 + rpRows * 32;
    CGFloat startY = (h - totalH) / 2;

    CGFloat contentW = 240;

    // Button dimensions
    CGFloat btnW = 180;
    CGFloat btnH = 40;
    CGFloat btnX = centerX - btnW / 2;
    CGFloat btnY = startY;

    // Draw button background
    NSBezierPath* btnPath = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(btnX, btnY, btnW, btnH)
                                                            xRadius:8 yRadius:8];
    [g_accent setFill];
    [btnPath fill];

    // Draw button text
    NSDictionary* attrs = @{
        NSFontAttributeName: self.uiFontBold,
        NSForegroundColorAttributeName: g_bg,
    };
    NSString* label = @"Start New Session";
    NSSize textSize = [label sizeWithAttributes:attrs];
    CGFloat textX = btnX + (btnW - textSize.width) / 2;
    CGFloat textY = btnY + (btnH - textSize.height) / 2;
    [label drawAtPoint:NSMakePoint(textX, textY) withAttributes:attrs];

    NSMutableParagraphStyle* truncStyle = [[NSMutableParagraphStyle alloc] init];
    truncStyle.lineBreakMode = NSLineBreakByTruncatingTail;

    NSDictionary* headerAttrs = @{
        NSFontAttributeName: self.uiFontSmall,
        NSForegroundColorAttributeName: g_textMuted,
        NSKernAttributeName: @1.5,
    };

    // SSH Remote section
    CGFloat sshY = btnY + btnH + 30;
    {
        CGFloat rowX = centerX - contentW / 2;

        NSString* sshHeader = @"REMOTE";
        [sshHeader drawAtPoint:NSMakePoint(rowX, sshY) withAttributes:headerAttrs];
        sshY += 24;
        CGFloat sshRowH = 30;
        CGFloat sshSubRowH = 28;

        for (uint16_t hi = 0; hi < sshCount; hi++) {
            uint8_t status = bridge_get_ssh_host_status(hi);
            uint8_t expanded = bridge_get_ssh_host_expanded(hi);

            // Host row
            NSRect hostRect = NSMakeRect(rowX, sshY, contentW, sshRowH);
            if (self.hoveredSshHost == hi) {
                [g_hoverBg setFill];
                NSBezierPath* hostPath = [NSBezierPath bezierPathWithRoundedRect:hostRect xRadius:6 yRadius:6];
                [hostPath fill];
            }

            // Status dot
            CGFloat dotX = rowX + 4;
            CGFloat dotY = sshY + (sshRowH - 6) / 2;
            NSColor* dotColor;
            switch (status) {
                case 2: dotColor = g_green; break;
                case 1: dotColor = g_accent; break;
                case 3: dotColor = hexColor(0xFF4444); break;
                default: dotColor = g_textMuted; break;
            }
            NSBezierPath* dot = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX, dotY, 6, 6)];
            [dotColor setFill];
            [dot fill];
            if (status == 0) {
                [g_bg setFill];
                [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(dotX + 1.5, dotY + 1.5, 3, 3)] fill];
            }

            // Expand arrow for connected hosts
            if (status == 2) {
                NSString* arrow = expanded ? @"\u25BE" : @"\u25B8";
                NSDictionary* arrowAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: g_textMuted,
                };
                [arrow drawAtPoint:NSMakePoint(rowX + contentW - 16, sshY + (sshRowH - 12) / 2) withAttributes:arrowAttrs];
            }

            // Spinner for connecting
            if (status == 1) {
                NSDictionary* spinAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:10 weight:NSFontWeightMedium],
                    NSForegroundColorAttributeName: g_accent,
                };
                [@"\u21BB" drawAtPoint:NSMakePoint(rowX + contentW - 16, sshY + (sshRowH - 12) / 2) withAttributes:spinAttrs];
            }

            // Host name
            uint16_t nameLen = bridge_get_ssh_host_name_len(hi);
            const uint8_t* namePtr = bridge_get_ssh_host_name(hi);
            NSString* hostName = [[NSString alloc] initWithBytes:namePtr length:nameLen encoding:NSUTF8StringEncoding];
            if (!hostName) hostName = @"?";

            NSDictionary* hostNameAttrs = @{
                NSFontAttributeName: self.uiFont,
                NSForegroundColorAttributeName: status == 2 ? g_text : g_textDim,
                NSParagraphStyleAttributeName: truncStyle,
            };
            [hostName drawInRect:NSMakeRect(rowX + 18, sshY + (sshRowH - 16) / 2, contentW - 40, sshRowH) withAttributes:hostNameAttrs];

            // × remove button on hover
            if (self.hoveredSshHost == hi) {
                NSDictionary* closeAttrs = @{
                    NSFontAttributeName: [NSFont systemFontOfSize:14 weight:NSFontWeightLight],
                    NSForegroundColorAttributeName: g_textMuted,
                };
                [@"\u00D7" drawAtPoint:NSMakePoint(rowX + contentW - 20, sshY + (sshRowH - 16) / 2) withAttributes:closeAttrs];
            }

            sshY += sshRowH;

            // Expanded sessions
            if (expanded && status == 2) {
                // Active local SSH sessions
                uint16_t activeCount = bridge_get_ssh_active_count(hi);
                for (uint16_t ai = 0; ai < activeCount; ai++) {
                    NSRect sessRect = NSMakeRect(rowX, sshY, contentW, sshSubRowH);
                    NSInteger encodedActive = hi * 100 + 50 + ai;
                    uint16_t sessIdx = bridge_get_ssh_active_session_idx(hi, ai);
                    uint8_t isSel = (sessIdx != 0xFFFF) ? bridge_is_session_selected(sessIdx) : 0;

                    if (isSel) {
                        [g_selectedBg setFill];
                        NSBezierPath* selPath = [NSBezierPath bezierPathWithRoundedRect:sessRect xRadius:6 yRadius:6];
                        [selPath fill];
                    } else if (self.hoveredSshSession == encodedActive) {
                        [g_hoverBg setFill];
                        NSBezierPath* hovPath = [NSBezierPath bezierPathWithRoundedRect:sessRect xRadius:6 yRadius:6];
                        [hovPath fill];
                    }

                    // Green dot
                    NSBezierPath* activeDot = [NSBezierPath bezierPathWithOvalInRect:
                        NSMakeRect(rowX + 18, sshY + (sshSubRowH - 5) / 2, 5, 5)];
                    [g_green setFill];
                    [activeDot fill];

                    uint16_t dLen = bridge_get_ssh_active_display_len(hi, ai);
                    const uint8_t* dPtr = bridge_get_ssh_active_display(hi, ai);
                    NSString* dName = [[NSString alloc] initWithBytes:dPtr length:dLen encoding:NSUTF8StringEncoding];
                    if (!dName) dName = @"?";

                    NSDictionary* activeAttrs = @{
                        NSFontAttributeName: isSel ? self.uiFontBold : self.uiFont,
                        NSForegroundColorAttributeName: isSel ? g_text : g_textDim,
                        NSParagraphStyleAttributeName: truncStyle,
                    };
                    [dName drawInRect:NSMakeRect(rowX + 30, sshY + (sshSubRowH - 14) / 2, contentW - 50, sshSubRowH) withAttributes:activeAttrs];
                    sshY += sshSubRowH;
                }

                // Remote tmux sessions
                uint16_t sessCount = bridge_get_ssh_session_count(hi);
                for (uint16_t si = 0; si < sessCount; si++) {
                    NSRect sessRect = NSMakeRect(rowX, sshY, contentW, sshSubRowH);
                    NSInteger encodedSess = hi * 100 + si;
                    if (self.hoveredSshSession == encodedSess) {
                        [g_hoverBg setFill];
                        NSBezierPath* hovPath = [NSBezierPath bezierPathWithRoundedRect:sessRect xRadius:6 yRadius:6];
                        [hovPath fill];
                    }

                    uint16_t sNameLen = bridge_get_ssh_session_name_len(hi, si);
                    const uint8_t* sNamePtr = bridge_get_ssh_session_name(hi, si);
                    NSString* sessName = [[NSString alloc] initWithBytes:sNamePtr length:sNameLen encoding:NSUTF8StringEncoding];
                    if (!sessName) sessName = @"?";

                    NSDictionary* sessAttrs = @{
                        NSFontAttributeName: self.uiFont,
                        NSForegroundColorAttributeName: g_textMuted,
                        NSParagraphStyleAttributeName: truncStyle,
                    };
                    [sessName drawInRect:NSMakeRect(rowX + 30, sshY + (sshSubRowH - 14) / 2, contentW - 50, sshSubRowH) withAttributes:sessAttrs];
                    sshY += sshSubRowH;
                }

                // "No sessions" hint
                if (activeCount == 0 && sessCount == 0) {
                    NSDictionary* emptyAttrs = @{
                        NSFontAttributeName: self.uiFont,
                        NSForegroundColorAttributeName: g_textMuted,
                    };
                    [@"No sessions" drawAtPoint:NSMakePoint(rowX + 30, sshY + (sshSubRowH - 14) / 2) withAttributes:emptyAttrs];
                    sshY += sshSubRowH;
                }

                // "+ New Session" row
                NSDictionary* newSessAttrs = @{
                    NSFontAttributeName: self.uiFont,
                    NSForegroundColorAttributeName: g_textMuted,
                };
                NSRect newSessRect = NSMakeRect(rowX, sshY, contentW, sshSubRowH);
                NSInteger encodedNewSess = hi * 100 + 99;
                if (self.hoveredSshSession == encodedNewSess) {
                    [g_hoverBg setFill];
                    NSBezierPath* hovPath = [NSBezierPath bezierPathWithRoundedRect:newSessRect xRadius:6 yRadius:6];
                    [hovPath fill];
                }
                [@"+ New Session" drawAtPoint:NSMakePoint(rowX + 30, sshY + (sshSubRowH - 14) / 2) withAttributes:newSessAttrs];
                sshY += sshSubRowH;
            }
        }

        // "+ Add Host" row
        NSDictionary* addHostAttrs = @{
            NSFontAttributeName: self.uiFont,
            NSForegroundColorAttributeName: g_textMuted,
        };
        NSString* addHostText = @"+ Add Host";
        NSSize addHostSize = [addHostText sizeWithAttributes:addHostAttrs];
        NSRect addHostRect = NSMakeRect(centerX - contentW / 2, sshY, contentW, 28);
        if (self.hoveredSshHost == -2) {
            [g_hoverBg setFill];
            NSBezierPath* hovPath = [NSBezierPath bezierPathWithRoundedRect:addHostRect xRadius:6 yRadius:6];
            [hovPath fill];
        }
        [addHostText drawAtPoint:NSMakePoint(rowX + 18, sshY + (28 - addHostSize.height) / 2) withAttributes:addHostAttrs];
        sshY += 28;
    }

    // Recent projects below SSH section
    CGFloat rpY = sshY + 20;

    NSString* headerLabel = @"RECENT PROJECTS";
    CGFloat rowX2Base = centerX - contentW / 2;
    [headerLabel drawAtPoint:NSMakePoint(rowX2Base, rpY) withAttributes:headerAttrs];
    rpY += 24;

    CGFloat rpRowH = 32;

    if (rpCount == 0) {
        NSDictionary* emptyAttrs = @{
            NSFontAttributeName: self.uiFont,
            NSForegroundColorAttributeName: g_textMuted,
        };
        NSString* emptyLabel = @"Nothing yet";
        NSSize emptySize = [emptyLabel sizeWithAttributes:emptyAttrs];
        [emptyLabel drawAtPoint:NSMakePoint(rowX2Base + 4, rpY + (rpRowH - emptySize.height) / 2) withAttributes:emptyAttrs];
    } else {
        for (uint16_t i = 0; i < rpCount; i++) {
            CGFloat rowX2 = centerX - contentW / 2;
            CGFloat rowY = rpY;
            NSRect rowRect = NSMakeRect(rowX2, rowY, contentW, rpRowH);

            if (self.hoveredRecentProject == (NSInteger)(i + 1000)) {
                [g_hoverBg setFill];
                NSBezierPath* rowPath = [NSBezierPath bezierPathWithRoundedRect:rowRect xRadius:6 yRadius:6];
                [rowPath fill];
            }

            uint16_t dLen = bridge_get_recent_project_display_len(i);
            const uint8_t* dPtr = bridge_get_recent_project_display(i);
            NSString* dName = [[NSString alloc] initWithBytes:dPtr length:dLen encoding:NSUTF8StringEncoding];
            if (!dName) dName = @"?";

            NSDictionary* rpAttrs = @{
                NSFontAttributeName: self.uiFont,
                NSForegroundColorAttributeName: g_textDim,
                NSParagraphStyleAttributeName: truncStyle,
            };
            NSSize nameSize = [dName sizeWithAttributes:rpAttrs];
            [dName drawInRect:NSMakeRect(rowX2 + 4, rowY + (rpRowH - nameSize.height) / 2, contentW - 8, rpRowH) withAttributes:rpAttrs];

            rpY += rpRowH;
        }
    }
}

- (void)drawTerminal {
    uint16_t cols = bridge_get_cols();
    uint16_t rows = bridge_get_rows();
    const BridgeCell* cells = bridge_get_cells();
    if (!cells) return;
    uint32_t cellCount = bridge_get_cell_count();

    CGFloat cw = self.cellWidth;
    CGFloat ch = self.cellHeight;
    CGFloat ox = [self sidebarPx] + kTermPadLeft;
    CGFloat oy = kTitlebarInset;

    for (uint16_t r = 0; r < rows; r++) {
        for (uint16_t c = 0; c < cols; c++) {
            uint32_t idx = (uint32_t)r * cols + c;
            if (idx >= cellCount) return;
            BridgeCell cell = cells[idx];
            CGFloat x = ox + c * cw;
            CGFloat y = oy + r * ch;

            uint32_t fgc = cell.fg;
            uint32_t bgc = cell.bg;

            // Reverse attribute
            if (cell.attrs & 4) {
                uint32_t tmp = fgc;
                fgc = bgc;
                bgc = tmp;
                if (fgc == 0xFFFFFFFF) fgc = 0x0A0A0A;
                if (bgc == 0xFFFFFFFF) bgc = 0xEDEDED;
            }

            // Selection highlight
            BOOL selected = [self isCellSelected:c row:r];
            if (selected) {
                bgc = 0x334477;
                if (fgc == 0xFFFFFFFF) fgc = 0xFFFFFF;
            }

            // Background (only draw if non-default or selected)
            if (bgc != 0xFFFFFFFF) {
                [colorFromU32(bgc, nil) setFill];
                NSRectFill(NSMakeRect(x, y, cw, ch));
            }

            // Character
            if (cell.ch > ' ') {
                NSColor* fg = colorFromU32(fgc, g_defaultFg);

                // Dim
                if (cell.attrs & 8) {
                    NSColor* s = [fg colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
                    if (s) {
                        CGFloat cr, cg, cb, ca;
                        [s getRed:&cr green:&cg blue:&cb alpha:&ca];
                        fg = [NSColor colorWithSRGBRed:cr*0.6 green:cg*0.6 blue:cb*0.6 alpha:ca];
                    }
                }

                // Font
                BOOL bold = (cell.attrs & 1) != 0;
                BOOL italic = (cell.attrs & 16) != 0;
                NSFont* font;
                if (bold && italic) font = self.boldItalicFont;
                else if (bold) font = self.boldFont;
                else if (italic) font = self.italicFont;
                else font = self.monoFont;

                // Render (full Unicode via UTF-32)
                uint32_t cp = cell.ch;
                NSString* str = [[NSString alloc] initWithBytes:&cp length:4
                                  encoding:NSUTF32LittleEndianStringEncoding];
                if (str) {
                    NSMutableDictionary* attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                        font, NSFontAttributeName,
                        fg, NSForegroundColorAttributeName, nil];
                    if (cell.attrs & 2) {
                        attrs[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
                    }
                    [str drawAtPoint:NSMakePoint(x, y) withAttributes:attrs];
                }
            }
        }
    }
}

- (void)drawCursor {
    CGFloat cw = self.cellWidth;
    CGFloat ch = self.cellHeight;
    CGFloat ox = [self sidebarPx] + kTermPadLeft;
    CGFloat oy = kTitlebarInset;
    uint16_t cx = bridge_get_cursor_x();
    uint16_t cy = bridge_get_cursor_y();

    NSRect r = NSMakeRect(ox + cx * cw, oy + cy * ch, cw, ch);

    // Thin bar cursor (modern style)
    [[g_cursor colorWithAlphaComponent:0.9] setFill];
    NSRectFill(NSMakeRect(r.origin.x, r.origin.y, 2, ch));
}

- (void)termColRow:(NSPoint)p col:(int*)outCol row:(int*)outRow {
    CGFloat ox = [self sidebarPx] + kTermPadLeft;
    CGFloat oy = kTitlebarInset;
    int c = (int)((p.x - ox) / self.cellWidth);
    int r = (int)((p.y - oy) / self.cellHeight);
    uint16_t cols = bridge_get_cols();
    uint16_t rows = bridge_get_rows();
    if (c < 0) c = 0;
    if (c >= cols) c = cols - 1;
    if (r < 0) r = 0;
    if (r >= rows) r = rows - 1;
    *outCol = c;
    *outRow = r;
}

- (BOOL)isCellSelected:(int)col row:(int)row {
    if (!self.hasSelection) return NO;
    int sr = self.selStartRow, sc = self.selStartCol;
    int er = self.selEndRow, ec = self.selEndCol;
    // Normalize so start <= end
    if (sr > er || (sr == er && sc > ec)) {
        int tr = sr, tc = sc; sr = er; sc = ec; er = tr; ec = tc;
    }
    if (row < sr || row > er) return NO;
    if (row == sr && row == er) return col >= sc && col <= ec;
    if (row == sr) return col >= sc;
    if (row == er) return col <= ec;
    return YES;
}

// === Mouse ===
- (void)mouseDown:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    // Handle palette click
    if (self.paletteVisible) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;

        if (self.paletteMode == 2) {
            // Add SSH host mode — click suggestion to add, click outside to dismiss
            int filteredIndices[32];
            int filteredCount = [self getFilteredSshSuggestionIndices:filteredIndices];
            CGFloat cardW = 360;
            CGFloat headerH = 44;
            CGFloat rowH = 34;
            CGFloat hintH = 28;
            int displayRows = filteredCount > 0 ? filteredCount : 0;
            CGFloat listH = displayRows * rowH;
            CGFloat cardH = headerH + listH + hintH + 12;
            CGFloat cardX = (w - cardW) / 2;
            CGFloat cardY = h * 0.2;
            if (p.x >= cardX && p.x <= cardX + cardW &&
                p.y >= cardY && p.y <= cardY + cardH) {
                // Check if click is on a suggestion row
                CGFloat itemY = cardY + headerH + 4;
                for (int fi = 0; fi < filteredCount; fi++) {
                    if (p.y >= itemY && p.y < itemY + rowH) {
                        int idx = filteredIndices[fi];
                        const uint8_t* nPtr = bridge_get_ssh_suggestion_name(idx);
                        uint16_t nLen = bridge_get_ssh_suggestion_name_len(idx);
                        bridge_add_ssh_host(nPtr, nLen);
                        self.paletteVisible = NO;
                        self.paletteMode = 0;
                        [self.paletteSearchText setString:@""];
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    itemY += rowH;
                }
                return; // absorb click inside card
            }
            // Click outside — dismiss
            self.paletteVisible = NO;
            self.paletteMode = 0;
            [self.paletteSearchText setString:@""];
            [self setNeedsDisplay:YES];
            return;
        }

        if (self.paletteMode == 1) {
            // Theme picker mode
            int filteredIndices[25];
            int filteredCount = [self getFilteredThemeIndices:filteredIndices];
            CGFloat cardW = 340;
            CGFloat rowH = 34;
            CGFloat headerH = 44;
            int maxVisible = 12;
            int displayCount = filteredCount > 0 ? (filteredCount < maxVisible ? filteredCount : maxVisible) : 1;
            CGFloat cardH = headerH + rowH * displayCount + 8;
            CGFloat cardX = (w - cardW) / 2;
            CGFloat cardY = h * 0.15;

            // Click on back button area (left 34px of header)
            if (p.x >= cardX && p.x < cardX + 34 &&
                p.y >= cardY && p.y < cardY + headerH) {
                applyTheme(g_savedTheme);
                self.paletteMode = 0;
                self.paletteSelection = kPaletteItemCount - 1;
                [self.paletteSearchText setString:@""];
                [self setNeedsDisplay:YES];
                return;
            }

            // Click in header (search bar area) — absorb
            if (p.x >= cardX && p.x <= cardX + cardW &&
                p.y >= cardY && p.y < cardY + headerH) {
                return;
            }

            // Click on a theme item — confirm selection
            CGFloat itemsTop = cardY + headerH + 4;
            if (p.x >= cardX && p.x <= cardX + cardW &&
                p.y >= itemsTop && p.y <= cardY + cardH) {
                int idx = (int)((p.y - itemsTop) / rowH);
                int filteredIdx = (int)(idx + self.themeScroll);
                if (filteredIdx >= 0 && filteredIdx < filteredCount) {
                    applyTheme(filteredIndices[filteredIdx]); // confirm
                    self.paletteVisible = NO;
                    self.paletteMode = 0;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                }
            }

            // Click outside dismisses — revert preview
            applyTheme(g_savedTheme);
            self.paletteVisible = NO;
            self.paletteMode = 0;
            [self.paletteSearchText setString:@""];
            [self setNeedsDisplay:YES];
            return;
        }

        // Commands mode
        int filteredIndices[9];
        int filteredCount = [self getFilteredCommandIndices:filteredIndices];
        CGFloat cardW = 320;
        CGFloat rowH = 38;
        CGFloat headerH = 44;
        int displayCount = filteredCount > 0 ? filteredCount : 1;
        CGFloat cardH = headerH + rowH * displayCount + 8;
        CGFloat cardX = (w - cardW) / 2;
        CGFloat cardY = h * 0.2;

        // Click in header (search bar area) — absorb
        if (p.x >= cardX && p.x <= cardX + cardW &&
            p.y >= cardY && p.y < cardY + headerH) {
            return;
        }

        if (p.x >= cardX && p.x <= cardX + cardW &&
            p.y >= cardY + headerH && p.y <= cardY + cardH) {
            int idx = (int)((p.y - cardY - headerH - 4) / rowH);
            if (idx >= 0 && idx < filteredCount) {
                int actualIdx = filteredIndices[idx];
                if (actualIdx == kPaletteItemCount - 1) {
                    // "Theme..." — switch to theme picker
                    g_savedTheme = g_currentTheme;
                    self.paletteMode = 1;
                    self.paletteSelection = g_currentTheme;
                    self.themeScroll = 0;
                    [self.paletteSearchText setString:@""];
                    if (self.paletteSelection >= 12) {
                        self.themeScroll = self.paletteSelection - 6;
                    }
                } else {
                    bridge_tmux_command((uint8_t)actualIdx);
                    self.paletteVisible = NO;
                    [self.paletteSearchText setString:@""];
                }
                [self setNeedsDisplay:YES];
                return;
            }
        }
        // Click outside dismisses
        self.paletteVisible = NO;
        self.paletteMode = 0;
        [self.paletteSearchText setString:@""];
        [self setNeedsDisplay:YES];
        return;
    }

    // Handle empty state clicks
    if (!bridge_is_started()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        CGFloat sbw = [self sidebarPx];
        CGFloat centerX = sbw + (w - sbw) / 2;

        uint16_t rpCount = bridge_get_recent_project_count();
        uint16_t sshCount = bridge_get_ssh_host_count();
        CGFloat rpRows = rpCount > 0 ? rpCount : 1;
        CGFloat sshSectionH = [self emptyStateSshSectionHeight];
        CGFloat totalH = 40 + 30 + sshSectionH + 20 + 24 + rpRows * 32;
        CGFloat startY = (h - totalH) / 2;

        CGFloat contentW = 240;
        CGFloat btnW = 180;
        CGFloat btnH = 40;
        CGFloat btnX = centerX - btnW / 2;
        CGFloat btnY = startY;

        if (p.x >= btnX && p.x <= btnX + btnW && p.y >= btnY && p.y <= btnY + btnH) {
            bridge_start_first_session();
            [self setNeedsDisplay:YES];
            return;
        }

        // SSH Remote section clicks
        CGFloat sshY = btnY + btnH + 30 + 24; // after REMOTE header
        CGFloat rowX = centerX - contentW / 2;
        {
            CGFloat sshRowH = 30;
            CGFloat sshSubRowH = 28;

            for (uint16_t hi = 0; hi < sshCount; hi++) {
                uint8_t status = bridge_get_ssh_host_status(hi);
                uint8_t expanded = bridge_get_ssh_host_expanded(hi);

                // Host row click
                if (p.y >= sshY && p.y < sshY + sshRowH && p.x >= rowX && p.x <= rowX + contentW) {
                    // × remove button (right 24px of row)
                    if (p.x >= rowX + contentW - 24) {
                        bridge_remove_ssh_host(hi);
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    bridge_toggle_ssh_host(hi);
                    [self setNeedsDisplay:YES];
                    return;
                }
                sshY += sshRowH;

                if (expanded && status == 2) {
                    // Active local SSH sessions
                    uint16_t activeCount = bridge_get_ssh_active_count(hi);
                    for (uint16_t ai = 0; ai < activeCount; ai++) {
                        if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                            uint16_t sessIdx = bridge_get_ssh_active_session_idx(hi, ai);
                            if (sessIdx != 0xFFFF) {
                                bridge_select_session(sessIdx);
                            }
                            [self setNeedsDisplay:YES];
                            return;
                        }
                        sshY += sshSubRowH;
                    }

                    // Remote tmux sessions
                    uint16_t sessCount = bridge_get_ssh_session_count(hi);
                    for (uint16_t si = 0; si < sessCount; si++) {
                        if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                            // × close button (right 24px)
                            if (p.x >= rowX + contentW - 24) {
                                bridge_kill_remote_session(hi, si);
                                [self setNeedsDisplay:YES];
                                return;
                            }
                            bridge_select_ssh_session(hi, si);
                            [self setNeedsDisplay:YES];
                            return;
                        }
                        sshY += sshSubRowH;
                    }

                    // "No sessions" placeholder
                    if (activeCount == 0 && sessCount == 0) {
                        sshY += sshSubRowH;
                    }

                    // "+ New Session" row
                    if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                        bridge_create_ssh_shell(hi);
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    sshY += sshSubRowH;
                }
            }

            // "+ Add Host" button
            if (p.y >= sshY && p.y < sshY + 28 && p.x >= rowX && p.x <= rowX + contentW) {
                [self promptAddSshHost];
                return;
            }
            sshY += 28;
        }

        // Recent project click (after SSH section)
        if (rpCount > 0) {
            CGFloat rpRowH = 32;
            CGFloat rpY = sshY + 20 + 24; // gap + header
            if (p.x >= rowX && p.x <= rowX + contentW && p.y >= rpY) {
                uint16_t rpIdx = (uint16_t)((p.y - rpY) / rpRowH);
                if (rpIdx < rpCount) {
                    uint16_t pathLen = bridge_get_recent_project_path_len(rpIdx);
                    const uint8_t* pathPtr = bridge_get_recent_project_path(rpIdx);
                    bridge_create_session_in_dir(pathPtr, pathLen);
                    [self setNeedsDisplay:YES];
                    return;
                }
            }
        }
    }

    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth) {
        uint16_t count = bridge_get_session_count();

        // Walk session rows, skipping SSH sessions (matching drawSidebar layout)
        CGFloat rowY = listTop;
        for (uint16_t i = 0; i < count; i++) {
            if (bridge_is_ssh_session(i)) continue;
            if (p.y >= rowY && p.y < rowY + kSessionRowH) {
                // Close button hit (right 28px of row)
                if (p.x >= kSidebarWidth - 28) {
                    if (self.closeArmedSession == i) {
                        self.closeArmedSession = -1;
                        bridge_kill_session(i);
                    } else {
                        self.closeArmedSession = i;
                        [self setNeedsDisplay:YES];
                    }
                    return;
                }
                if (event.clickCount == 2) {
                    [self promptRenameSession:i];
                    return;
                }
                self.closeArmedSession = -1;
                bridge_select_session(i);
                return;
            }
            rowY += kSessionRowH;
        }
        CGFloat sessionsEnd = rowY;
        CGFloat btnEnd = sessionsEnd + kNewBtnHeight;

        // "+ New Session" button
        if (p.y >= sessionsEnd && p.y < btnEnd) {
            bridge_create_session();
            return;
        }

        // Compute SSH section layout (same flow as drawSidebar)
        CGFloat sshY = btnEnd;
        uint16_t sshCount = bridge_get_ssh_host_count();
        {
            CGFloat sshHeaderEnd = sshY + kRecentHeaderH; // REMOTE header
            if (p.y >= sshY && p.y < sshHeaderEnd) {
                return; // click on header, ignore
            }
            CGFloat sshItemY = sshHeaderEnd;
            for (uint16_t hi = 0; hi < sshCount; hi++) {
                uint8_t status = bridge_get_ssh_host_status(hi);
                uint8_t expanded = bridge_get_ssh_host_expanded(hi);

                // Host row
                if (p.y >= sshItemY && p.y < sshItemY + kSessionRowH) {
                    // × remove button (right 28px)
                    if (p.x >= kSidebarWidth - 28) {
                        bridge_remove_ssh_host(hi);
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    bridge_toggle_ssh_host(hi);
                    [self setNeedsDisplay:YES];
                    return;
                }
                sshItemY += kSessionRowH;

                // Sessions under expanded host
                if (expanded && status == 2) {
                    // Active local SSH sessions
                    uint16_t activeCount = bridge_get_ssh_active_count(hi);
                    for (uint16_t ai = 0; ai < activeCount; ai++) {
                        if (p.y >= sshItemY && p.y < sshItemY + kRecentRowH) {
                            uint16_t sessIdx = bridge_get_ssh_active_session_idx(hi, ai);
                            if (sessIdx != 0xFFFF) {
                                // × close button (right 28px)
                                if (p.x >= kSidebarWidth - 28) {
                                    bridge_kill_session(sessIdx);
                                    [self setNeedsDisplay:YES];
                                    return;
                                }
                                bridge_select_session(sessIdx);
                            }
                            [self setNeedsDisplay:YES];
                            return;
                        }
                        sshItemY += kRecentRowH;
                    }

                    // Remote tmux sessions (from probe)
                    uint16_t sessCount = bridge_get_ssh_session_count(hi);
                    for (uint16_t si = 0; si < sessCount; si++) {
                        if (p.y >= sshItemY && p.y < sshItemY + kRecentRowH) {
                            // × close button (right 28px)
                            if (p.x >= kSidebarWidth - 28) {
                                bridge_kill_remote_session(hi, si);
                                [self setNeedsDisplay:YES];
                                return;
                            }
                            bridge_select_ssh_session(hi, si);
                            [self setNeedsDisplay:YES];
                            return;
                        }
                        sshItemY += kRecentRowH;
                    }

                    // "No sessions" placeholder
                    if (activeCount == 0 && sessCount == 0) {
                        sshItemY += kRecentRowH;
                    }

                    // "+ New Session" row
                    if (p.y >= sshItemY && p.y < sshItemY + kRecentRowH) {
                        bridge_create_ssh_shell(hi);
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    sshItemY += kRecentRowH;
                }
            }

            // "+ Add Host" button
            CGFloat addHostBtnH = kNewBtnHeight * 0.7;
            if (p.y >= sshItemY && p.y < sshItemY + addHostBtnH) {
                [self promptAddSshHost];
                return;
            }
            sshY = sshItemY + addHostBtnH;
        }

        // Recent projects click (after SSH section)
        uint16_t rpCount = bridge_get_recent_project_count();
        if (rpCount > 0) {
            CGFloat rpStart = sshY + kRecentHeaderH; // after RECENT PROJECTS header
            if (p.y >= rpStart) {
                uint16_t rpIdx = (uint16_t)((p.y - rpStart) / kRecentRowH);
                if (rpIdx < rpCount) {
                    // × button (right 28px)
                    if (p.x >= kSidebarWidth - 28) {
                        bridge_remove_recent_project(rpIdx);
                        [self setNeedsDisplay:YES];
                        return;
                    }
                    uint16_t pathLen = bridge_get_recent_project_path_len(rpIdx);
                    const uint8_t* pathPtr = bridge_get_recent_project_path(rpIdx);
                    bridge_create_session_in_dir(pathPtr, pathLen);
                    return;
                }
            }
        }

        return;
    }

    // Terminal area
    int c, r;
    [self termColRow:p col:&c row:&r];

    if (event.clickCount == 2) {
        // Double-click: select entire line
        uint16_t cols = bridge_get_cols();
        self.selStartCol = 0;
        self.selStartRow = r;
        self.selEndCol = cols - 1;
        self.selEndRow = r;
        self.hasSelection = YES;
        self.isDragging = NO;
        [self setNeedsDisplay:YES];
        [self.window makeFirstResponder:self];
        return;
    }

    // Send mouse click to tmux (for pane selection, etc.)
    // xterm mouse protocol: ESC [ M <button+32> <col+33> <row+33>
    uint8_t mouseDown[6] = {0x1b, '[', 'M', 0 + 32, (uint8_t)(c + 33), (uint8_t)(r + 33)};
    bridge_key_input(mouseDown, 6);
    // Mouse release
    uint8_t mouseUp[6] = {0x1b, '[', 'M', 3 + 32, (uint8_t)(c + 33), (uint8_t)(r + 33)};
    bridge_key_input(mouseUp, 6);

    // Single click — start drag selection, clear previous
    self.hasSelection = NO;
    self.selStartCol = c;
    self.selStartRow = r;
    self.selEndCol = c;
    self.selEndRow = r;
    self.isDragging = YES;
    [self setNeedsDisplay:YES];
    [self.window makeFirstResponder:self];
}

- (void)rightMouseDown:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth && p.y >= listTop) {
        uint16_t count = bridge_get_session_count();
        CGFloat rowY = listTop;
        for (uint16_t i = 0; i < count; i++) {
            if (bridge_is_ssh_session(i)) continue;
            if (p.y >= rowY && p.y < rowY + kSessionRowH) {
                [self showContextMenuForSession:i event:event];
                return;
            }
            rowY += kSessionRowH;
        }
    }
    [super rightMouseDown:event];
}

- (void)showContextMenuForSession:(uint16_t)idx event:(NSEvent*)event {
    NSMenu* menu = [[NSMenu alloc] init];
    NSMenuItem* renameItem = [[NSMenuItem alloc] initWithTitle:@"Rename"
        action:@selector(contextRename:) keyEquivalent:@""];
    renameItem.tag = idx;
    renameItem.target = self;
    [menu addItem:renameItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* deleteItem = [[NSMenuItem alloc] initWithTitle:@"Delete"
        action:@selector(contextDelete:) keyEquivalent:@""];
    deleteItem.tag = idx;
    deleteItem.target = self;
    [menu addItem:deleteItem];

    [NSMenu popUpContextMenu:menu withEvent:event forView:self];
}

- (void)contextRename:(NSMenuItem*)item {
    [self promptRenameSession:(uint16_t)item.tag];
}

- (void)contextDelete:(NSMenuItem*)item {
    bridge_kill_session((uint16_t)item.tag);
}

- (void)promptRenameSession:(uint16_t)idx {
    uint16_t nameLen = bridge_get_session_name_len(idx);
    const uint8_t* namePtr = bridge_get_session_name(idx);
    NSString* currentName = [[NSString alloc] initWithBytes:namePtr length:nameLen encoding:NSUTF8StringEncoding];

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Session";
    alert.informativeText = @"";
    alert.icon = nil; // No icon — clean look
    alert.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [alert addButtonWithTitle:@"Rename"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField* input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 28)];
    input.stringValue = currentName ?: @"";
    input.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
    input.bezelStyle = NSTextFieldRoundedBezel;
    input.focusRingType = NSFocusRingTypeNone;
    alert.accessoryView = input;
    [alert.window setInitialFirstResponder:input];

    NSModalResponse resp = [alert runModal];
    if (resp == NSAlertFirstButtonReturn) {
        NSString* newName = input.stringValue;
        if (newName.length > 0) {
            const char* utf8 = [newName UTF8String];
            bridge_rename_session(idx, (const uint8_t*)utf8, (uint16_t)strlen(utf8));
        }
    }
    [self.window makeFirstResponder:self];
}

- (void)promptAddSshHost {
    // Open the palette in "add SSH host" mode
    bridge_load_ssh_suggestions();
    self.paletteVisible = YES;
    self.paletteMode = 2;
    self.paletteSelection = 0;
    [self.paletteSearchText setString:@""];
    [self setNeedsDisplay:YES];
}

// === Drag and Drop ===
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard* pb = [sender draggingPasteboard];
    if ([pb canReadObjectForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard* pb = [sender draggingPasteboard];
    NSArray<NSURL*>* urls = [pb readObjectsForClasses:@[[NSURL class]]
                                              options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (!urls || urls.count == 0) return NO;

    NSMutableArray<NSString*>* paths = [NSMutableArray array];
    for (NSURL* url in urls) {
        NSString* path = url.path;
        if (path) {
            // Shell-escape spaces and special characters
            path = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
            path = [path stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
            path = [path stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
            path = [path stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
            path = [path stringByReplacingOccurrencesOfString:@"(" withString:@"\\("];
            path = [path stringByReplacingOccurrencesOfString:@")" withString:@"\\)"];
            [paths addObject:path];
        }
    }

    NSString* combined = [paths componentsJoinedByString:@" "];
    if (combined.length > 0) {
        const char* utf8 = [combined UTF8String];
        if (utf8) {
            bridge_key_input((const uint8_t*)utf8, (uint32_t)strlen(utf8));
        }
    }
    return YES;
}


- (void)mouseMoved:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    // Palette hover
    if (self.paletteVisible) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;

        if (self.paletteMode == 1) {
            // Theme picker hover
            int filteredIndices[25];
            int filteredCount = [self getFilteredThemeIndices:filteredIndices];
            CGFloat cardW = 340;
            CGFloat rowH = 34;
            CGFloat headerH = 44;
            CGFloat cardX = (w - cardW) / 2;
            CGFloat cardY = h * 0.15;
            CGFloat itemsTop = cardY + headerH + 4;

            if (p.x >= cardX && p.x <= cardX + cardW && p.y >= itemsTop) {
                int idx = (int)((p.y - itemsTop) / rowH);
                int filteredIdx = (int)(idx + self.themeScroll);
                if (filteredIdx >= 0 && filteredIdx < filteredCount && filteredIdx != self.paletteSelection) {
                    self.paletteSelection = filteredIdx;
                    applyTheme(filteredIndices[filteredIdx]); // live preview on hover
                    [self setNeedsDisplay:YES];
                }
            }
        } else if (self.paletteMode == 0) {
            // Commands hover
            int filteredIndices[9];
            int filteredCount = [self getFilteredCommandIndices:filteredIndices];
            CGFloat cardW = 320;
            CGFloat rowH = 38;
            CGFloat headerH = 44;
            CGFloat cardX = (w - cardW) / 2;
            CGFloat cardY = h * 0.2;
            CGFloat itemsTop = cardY + headerH + 4;

            if (p.x >= cardX && p.x <= cardX + cardW && p.y >= itemsTop) {
                int idx = (int)((p.y - itemsTop) / rowH);
                if (idx >= 0 && idx < filteredCount && idx != self.paletteSelection) {
                    self.paletteSelection = idx;
                    [self setNeedsDisplay:YES];
                }
            }
        }
        [[NSCursor pointingHandCursor] set];
        return;
    }

    NSInteger oldSession = self.hoveredSession;
    NSInteger oldRecent = self.hoveredRecentProject;
    NSInteger oldSshHost = self.hoveredSshHost;
    NSInteger oldSshSession = self.hoveredSshSession;
    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    self.hoveredSession = -1;
    self.hoveredRecentProject = -1;
    self.hoveredSshHost = -1;
    self.hoveredSshSession = -1;

    // Empty state recent projects hover (offset by 1000 to distinguish from sidebar)
    if (!bridge_is_started()) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        CGFloat sbw = [self sidebarPx];
        CGFloat centerX = sbw + (w - sbw) / 2;
        uint16_t rpCount = bridge_get_recent_project_count();
        uint16_t sshCount = bridge_get_ssh_host_count();
        CGFloat rpRows = rpCount > 0 ? rpCount : 1;
        CGFloat sshSectionH = [self emptyStateSshSectionHeight];
        CGFloat totalH = 40 + 30 + sshSectionH + 20 + 24 + rpRows * 32;
        CGFloat startY = (h - totalH) / 2;
        CGFloat contentW = 240;
        CGFloat rowX = centerX - contentW / 2;

        // SSH section hover
        CGFloat sshY = startY + 40 + 30 + 24; // btn + gap + REMOTE header
        {
            CGFloat sshRowH = 30;
            CGFloat sshSubRowH = 28;
            BOOL inSsh = NO;

            for (uint16_t hi = 0; hi < sshCount; hi++) {
                uint8_t status = bridge_get_ssh_host_status(hi);
                uint8_t expanded = bridge_get_ssh_host_expanded(hi);

                if (p.y >= sshY && p.y < sshY + sshRowH && p.x >= rowX && p.x <= rowX + contentW) {
                    self.hoveredSshHost = hi;
                    inSsh = YES;
                    break;
                }
                sshY += sshRowH;

                if (expanded && status == 2) {
                    uint16_t activeCount = bridge_get_ssh_active_count(hi);
                    for (uint16_t ai = 0; ai < activeCount; ai++) {
                        if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                            self.hoveredSshSession = hi * 100 + 50 + ai;
                            inSsh = YES;
                            break;
                        }
                        sshY += sshSubRowH;
                    }
                    if (inSsh) break;

                    uint16_t sessCount = bridge_get_ssh_session_count(hi);
                    for (uint16_t si = 0; si < sessCount; si++) {
                        if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                            self.hoveredSshSession = hi * 100 + si;
                            inSsh = YES;
                            break;
                        }
                        sshY += sshSubRowH;
                    }
                    if (inSsh) break;

                    if (activeCount == 0 && sessCount == 0) sshY += sshSubRowH;

                    // "+ New Session" row
                    if (p.y >= sshY && p.y < sshY + sshSubRowH && p.x >= rowX && p.x <= rowX + contentW) {
                        self.hoveredSshSession = hi * 100 + 99;
                        inSsh = YES;
                        break;
                    }
                    sshY += sshSubRowH;
                }
            }

            // "+ Add Host" button
            if (!inSsh && p.y >= sshY && p.y < sshY + 28 && p.x >= rowX && p.x <= rowX + contentW) {
                self.hoveredSshHost = -2;
                inSsh = YES;
            }
            if (!inSsh) sshY += 28; else sshY = sshY; // no-op, sshY already advanced
        }

        // Recent projects hover (after SSH section)
        CGFloat rpSectionY = startY + 40 + 30 + sshSectionH + 20 + 24; // after all sections + headers
        if (rpCount > 0) {
            CGFloat rpRowH = 32;
            if (p.x >= rowX && p.x <= rowX + contentW && p.y >= rpSectionY) {
                NSInteger rpIdx = (NSInteger)((p.y - rpSectionY) / rpRowH);
                if (rpIdx >= 0 && rpIdx < rpCount) {
                    self.hoveredRecentProject = rpIdx + 1000;
                }
            }
        }
    }

    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth && p.y >= listTop) {
        uint16_t count = bridge_get_session_count();

        // Walk session rows, skipping SSH sessions (matching drawSidebar layout)
        CGFloat rowY = listTop;
        for (uint16_t i = 0; i < count; i++) {
            if (bridge_is_ssh_session(i)) continue;
            if (p.y >= rowY && p.y < rowY + kSessionRowH) {
                self.hoveredSession = i;
                break;
            }
            rowY += kSessionRowH;
        }
        CGFloat sessionsEnd = rowY;
        CGFloat btnEnd = sessionsEnd + kNewBtnHeight;

        if (p.y >= btnEnd) {
            // Walk SSH section layout to determine hover
            CGFloat sshY = btnEnd;
            uint16_t sshCount = bridge_get_ssh_host_count();
            BOOL inSsh = NO;
            {
                CGFloat sshItemY = sshY + kRecentHeaderH; // after REMOTE header
                for (uint16_t hi = 0; hi < sshCount; hi++) {
                    uint8_t status = bridge_get_ssh_host_status(hi);
                    uint8_t expanded = bridge_get_ssh_host_expanded(hi);
                    // Host row
                    if (p.y >= sshItemY && p.y < sshItemY + kSessionRowH) {
                        self.hoveredSshHost = hi;
                        inSsh = YES;
                        break;
                    }
                    sshItemY += kSessionRowH;
                    if (expanded && status == 2) {
                        // Active local SSH sessions
                        uint16_t activeCount = bridge_get_ssh_active_count(hi);
                        for (uint16_t ai = 0; ai < activeCount; ai++) {
                            if (p.y >= sshItemY && p.y < sshItemY + kRecentRowH) {
                                self.hoveredSshSession = hi * 100 + 50 + ai;
                                inSsh = YES;
                                break;
                            }
                            sshItemY += kRecentRowH;
                        }
                        if (inSsh) break;

                        // Remote tmux sessions
                        uint16_t sessCount = bridge_get_ssh_session_count(hi);
                        for (uint16_t si = 0; si < sessCount; si++) {
                            if (p.y >= sshItemY && p.y < sshItemY + kRecentRowH) {
                                self.hoveredSshSession = hi * 100 + si;
                                inSsh = YES;
                                break;
                            }
                            sshItemY += kRecentRowH;
                        }
                        if (inSsh) break;

                        // "No sessions" placeholder
                        if (activeCount == 0 && sessCount == 0) {
                            sshItemY += kRecentRowH;
                        }

                        sshItemY += kRecentRowH; // "+ New Session" row
                    }
                }
                sshY = sshItemY + kNewBtnHeight * 0.7; // + Add Host button
            }
            // Check recent projects area (after SSH section)
            if (!inSsh) {
                uint16_t rpCount = bridge_get_recent_project_count();
                if (rpCount > 0) {
                    CGFloat rpStart = sshY + kRecentHeaderH;
                    if (p.y >= rpStart) {
                        NSInteger rpIdx = (NSInteger)((p.y - rpStart) / kRecentRowH);
                        if (rpIdx >= 0 && rpIdx < rpCount) self.hoveredRecentProject = rpIdx;
                    }
                }
            }
        }
    }

    if (oldSession != self.hoveredSession || oldRecent != self.hoveredRecentProject ||
        oldSshHost != self.hoveredSshHost || oldSshSession != self.hoveredSshSession) {
        [self setNeedsDisplay:YES];
    }

    // Cursor style
    if ((bridge_is_sidebar_visible() && p.x < kSidebarWidth && p.y >= listTop) ||
        self.hoveredRecentProject >= 1000 ||
        (!bridge_is_started() && (self.hoveredSshHost >= 0 || self.hoveredSshHost == -2 || self.hoveredSshSession >= 0))) {
        [[NSCursor pointingHandCursor] set];
    } else {
        [[NSCursor IBeamCursor] set];
    }
}

- (void)scrollWheel:(NSEvent*)event {
    if (self.paletteVisible) {
        if (self.paletteMode == 1) {
            // Scroll theme list (filtered)
            int filteredIndices[25];
            int filteredCount = [self getFilteredThemeIndices:filteredIndices];
            CGFloat dy = event.scrollingDeltaY;
            if (event.hasPreciseScrollingDeltas) dy /= 10.0;
            int lines = (int)dy;
            if (lines == 0 && dy != 0) lines = (dy > 0) ? 1 : -1;
            if (lines == 0) return;
            NSInteger newScroll = self.themeScroll - lines;
            NSInteger maxScroll = filteredCount - 12;
            if (maxScroll < 0) maxScroll = 0;
            if (newScroll < 0) newScroll = 0;
            if (newScroll > maxScroll) newScroll = maxScroll;
            if (newScroll != self.themeScroll) {
                self.themeScroll = newScroll;
                [self setNeedsDisplay:YES];
            }
        }
        return;
    }
    CGFloat dy = event.scrollingDeltaY;
    if (event.hasPreciseScrollingDeltas) dy /= 3.0; // trackpad
    int lines = (int)dy;
    if (lines == 0 && dy != 0) lines = (dy > 0) ? 1 : -1;
    if (lines == 0) return;

    // Convert mouse position to terminal coordinates for mouse wheel escape
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    int col, row;
    [self termColRow:p col:&col row:&row];

    // Send xterm mouse wheel events (button 64=scroll up, 65=scroll down)
    // Format: ESC [ M <button+32> <col+33> <row+33>
    for (int i = 0; i < abs(lines); i++) {
        uint8_t btn = (lines > 0) ? 64 : 65; // 64=up, 65=down
        uint8_t buf[6];
        buf[0] = 0x1b;
        buf[1] = '[';
        buf[2] = 'M';
        buf[3] = (uint8_t)(btn + 32);
        buf[4] = (uint8_t)(col + 33);
        buf[5] = (uint8_t)(row + 33);
        bridge_key_input(buf, 6);
    }
}

- (void)mouseDragged:(NSEvent*)event {
    if (!self.isDragging) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    int c, r;
    [self termColRow:p col:&c row:&r];
    self.selEndCol = c;
    self.selEndRow = r;
    self.hasSelection = (self.selStartCol != self.selEndCol || self.selStartRow != self.selEndRow);
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent*)event {
    (void)event;
    self.isDragging = NO;
}

- (NSString*)selectedText {
    if (!self.hasSelection) return nil;
    uint16_t cols = bridge_get_cols();
    const BridgeCell* cells = bridge_get_cells();
    if (!cells) return nil;

    int sr = self.selStartRow, sc = self.selStartCol;
    int er = self.selEndRow, ec = self.selEndCol;
    if (sr > er || (sr == er && sc > ec)) {
        int tr = sr, tc = sc; sr = er; sc = ec; er = tr; ec = tc;
    }

    NSMutableString* text = [NSMutableString string];
    for (int r = sr; r <= er; r++) {
        int cStart = (r == sr) ? sc : 0;
        int cEnd = (r == er) ? ec : cols - 1;
        // Find last non-space in row to trim trailing spaces
        int lastNonSpace = cStart - 1;
        for (int c = cStart; c <= cEnd; c++) {
            uint32_t ch = cells[r * cols + c].ch;
            if (ch > ' ') lastNonSpace = c;
        }
        for (int c = cStart; c <= lastNonSpace; c++) {
            uint32_t cp = cells[r * cols + c].ch;
            if (cp == 0) cp = ' ';
            NSString* s = [[NSString alloc] initWithBytes:&cp length:4
                            encoding:NSUTF32LittleEndianStringEncoding];
            if (s) [text appendString:s];
        }
        if (r < er) [text appendString:@"\n"];
    }
    return text;
}

// === Keyboard ===
- (void)keyDown:(NSEvent*)event {
    // Command palette navigation — swallows all keys while visible.
    // Theme mode uses live preview: up/down calls applyTheme() immediately,
    // Enter confirms (theme already applied), Escape reverts to g_savedTheme.
    if (self.paletteVisible) {
        if (self.paletteMode == 2) {
            // Add SSH host mode: type host, up/down to pick from ssh config, Enter to add
            int filteredIndices[32];
            int filteredCount = [self getFilteredSshSuggestionIndices:filteredIndices];
            switch (event.keyCode) {
                case 126: { // Up
                    if (filteredCount > 0 && self.paletteSelection > 0) {
                        self.paletteSelection--;
                    }
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 125: { // Down
                    if (filteredCount > 0 && self.paletteSelection < filteredCount - 1) {
                        self.paletteSelection++;
                    }
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 36: { // Enter — add selected suggestion or typed text
                    if (filteredCount > 0 && self.paletteSelection < filteredCount) {
                        // Add the selected suggestion
                        int idx = filteredIndices[self.paletteSelection];
                        const uint8_t* nPtr = bridge_get_ssh_suggestion_name(idx);
                        uint16_t nLen = bridge_get_ssh_suggestion_name_len(idx);
                        bridge_add_ssh_host(nPtr, nLen);
                    } else if (self.paletteSearchText.length > 0) {
                        // Add typed text as custom host
                        const char* utf8 = [self.paletteSearchText UTF8String];
                        bridge_add_ssh_host((const uint8_t*)utf8, (uint16_t)strlen(utf8));
                    }
                    self.paletteVisible = NO;
                    self.paletteMode = 0;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 53: { // Escape — cancel
                    self.paletteVisible = NO;
                    self.paletteMode = 0;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 51: { // Backspace
                    if (self.paletteSearchText.length > 0) {
                        [self.paletteSearchText deleteCharactersInRange:
                            NSMakeRange(self.paletteSearchText.length - 1, 1)];
                        self.paletteSelection = 0;
                        [self setNeedsDisplay:YES];
                    }
                    return;
                }
                default: {
                    NSString* chars = event.characters;
                    if (chars.length > 0) {
                        unichar ch = [chars characterAtIndex:0];
                        if (ch >= 0x20 && ch < 0x7F) {
                            [self.paletteSearchText appendString:chars];
                            self.paletteSelection = 0;
                            [self setNeedsDisplay:YES];
                        }
                    }
                    return;
                }
            }
        }
        if (self.paletteMode == 1) {
            // Theme picker: navigate + live preview + search
            int filteredIndices[25];
            int filteredCount = [self getFilteredThemeIndices:filteredIndices];
            switch (event.keyCode) {
                case 126: { // Up
                    if (filteredCount > 0 && self.paletteSelection > 0) {
                        self.paletteSelection--;
                        if (self.paletteSelection < self.themeScroll) {
                            self.themeScroll = self.paletteSelection;
                        }
                        applyTheme(filteredIndices[self.paletteSelection]);
                    }
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 125: { // Down
                    if (filteredCount > 0 && self.paletteSelection < filteredCount - 1) {
                        self.paletteSelection++;
                        int visibleItems = filteredCount < 12 ? filteredCount : 12;
                        if (self.paletteSelection >= self.themeScroll + visibleItems) {
                            self.themeScroll = self.paletteSelection - visibleItems + 1;
                        }
                        applyTheme(filteredIndices[self.paletteSelection]);
                    }
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 36: { // Enter — confirm theme
                    if (filteredCount > 0 && self.paletteSelection < filteredCount) {
                        applyTheme(filteredIndices[self.paletteSelection]);
                    }
                    self.paletteVisible = NO;
                    self.paletteMode = 0;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 53: { // Escape — revert and go back
                    applyTheme(g_savedTheme);
                    self.paletteMode = 0;
                    self.paletteSelection = kPaletteItemCount - 1;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                }
                case 51: { // Delete/Backspace
                    if (self.paletteSearchText.length > 0) {
                        [self.paletteSearchText deleteCharactersInRange:
                            NSMakeRange(self.paletteSearchText.length - 1, 1)];
                        self.paletteSelection = 0;
                        self.themeScroll = 0;
                        int newFiltered[25];
                        int newCount = [self getFilteredThemeIndices:newFiltered];
                        if (newCount > 0) {
                            applyTheme(newFiltered[0]);
                        }
                        [self setNeedsDisplay:YES];
                    } else {
                        // Empty search — go back to commands
                        applyTheme(g_savedTheme);
                        self.paletteMode = 0;
                        self.paletteSelection = kPaletteItemCount - 1;
                        [self setNeedsDisplay:YES];
                    }
                    return;
                }
                default: {
                    NSString* chars = event.characters;
                    if (chars.length > 0) {
                        unichar ch = [chars characterAtIndex:0];
                        if (ch >= 0x20 && ch < 0x7F) {
                            [self.paletteSearchText appendString:chars];
                            self.paletteSelection = 0;
                            self.themeScroll = 0;
                            int newFiltered[25];
                            int newCount = [self getFilteredThemeIndices:newFiltered];
                            if (newCount > 0) {
                                applyTheme(newFiltered[0]);
                            }
                            [self setNeedsDisplay:YES];
                        }
                    }
                    return;
                }
            }
        } else {
            // Commands mode: navigate + search
            int filteredIndices[9];
            int filteredCount = [self getFilteredCommandIndices:filteredIndices];
            switch (event.keyCode) {
                case 126: // Up
                    if (filteredCount > 0) {
                        self.paletteSelection = (self.paletteSelection - 1 + filteredCount) % filteredCount;
                    }
                    [self setNeedsDisplay:YES];
                    return;
                case 125: // Down
                    if (filteredCount > 0) {
                        self.paletteSelection = (self.paletteSelection + 1) % filteredCount;
                    }
                    [self setNeedsDisplay:YES];
                    return;
                case 36: { // Enter
                    if (filteredCount > 0 && self.paletteSelection < filteredCount) {
                        int actualIdx = filteredIndices[self.paletteSelection];
                        if (actualIdx == kPaletteItemCount - 1) {
                            // "Theme..." — switch to theme picker mode
                            g_savedTheme = g_currentTheme;
                            self.paletteMode = 1;
                            self.paletteSelection = g_currentTheme;
                            self.themeScroll = 0;
                            [self.paletteSearchText setString:@""];
                            if (self.paletteSelection >= 12) {
                                self.themeScroll = self.paletteSelection - 6;
                            }
                            [self setNeedsDisplay:YES];
                        } else {
                            bridge_tmux_command((uint8_t)actualIdx);
                            self.paletteVisible = NO;
                            [self.paletteSearchText setString:@""];
                            [self setNeedsDisplay:YES];
                        }
                    }
                    return;
                }
                case 53: // Escape
                    self.paletteVisible = NO;
                    self.paletteMode = 0;
                    [self.paletteSearchText setString:@""];
                    [self setNeedsDisplay:YES];
                    return;
                case 51: { // Backspace
                    if (self.paletteSearchText.length > 0) {
                        [self.paletteSearchText deleteCharactersInRange:
                            NSMakeRange(self.paletteSearchText.length - 1, 1)];
                        self.paletteSelection = 0;
                        [self setNeedsDisplay:YES];
                    }
                    return;
                }
                default: {
                    NSString* chars = event.characters;
                    if (chars.length > 0) {
                        unichar ch = [chars characterAtIndex:0];
                        if (ch >= 0x20 && ch < 0x7F) {
                            [self.paletteSearchText appendString:chars];
                            self.paletteSelection = 0;
                            [self setNeedsDisplay:YES];
                        }
                    }
                    return;
                }
            }
        }
    }

    if (event.modifierFlags & NSEventModifierFlagCommand) {
        NSString* chars = event.charactersIgnoringModifiers;
        // Cmd+K — toggle command palette
        if ([chars isEqualToString:@"k"]) {
            if (self.paletteVisible && self.paletteMode == 1) {
                // Closing while in theme preview — revert
                applyTheme(g_savedTheme);
            }
            self.paletteVisible = !self.paletteVisible;
            self.paletteSelection = 0;
            self.paletteMode = 0;
            self.themeScroll = 0;
            [self.paletteSearchText setString:@""];
            [self setNeedsDisplay:YES];
            return;
        }
        if ([chars isEqualToString:@"c"] && self.hasSelection) {
            // Cmd+C — copy selection
            NSString* text = [self selectedText];
            if (text) {
                NSPasteboard* pb = [NSPasteboard generalPasteboard];
                [pb clearContents];
                [pb setString:text forType:NSPasteboardTypeString];
            }
            self.hasSelection = NO;
            [self setNeedsDisplay:YES];
            return;
        }
        if ([chars isEqualToString:@"v"]) {
            // Cmd+V — paste
            NSPasteboard* pb = [NSPasteboard generalPasteboard];
            NSString* text = [pb stringForType:NSPasteboardTypeString];
            if (text) {
                // Bracket paste mode: wrap in ESC[200~ ... ESC[201~
                const char* utf8 = [text UTF8String];
                if (utf8) {
                    bridge_key_input((const uint8_t*)"\x1b[200~", 6);
                    bridge_key_input((const uint8_t*)utf8, (uint32_t)strlen(utf8));
                    bridge_key_input((const uint8_t*)"\x1b[201~", 6);
                }
            }
            return;
        }
        [super keyDown:event];
        return;
    }

    // Option+key → send ESC + key (Meta)
    if (event.modifierFlags & NSEventModifierFlagOption) {
        NSString* chars = event.charactersIgnoringModifiers;
        if (chars && chars.length > 0) {
            const char* utf8 = [chars UTF8String];
            if (utf8) {
                bridge_key_input((const uint8_t*)"\x1b", 1);
                bridge_key_input((const uint8_t*)utf8, (uint32_t)strlen(utf8));
            }
        }
        return;
    }

    switch (event.keyCode) {
        case 126: bridge_key_input((const uint8_t*)"\x1b[A", 3); return;
        case 125: bridge_key_input((const uint8_t*)"\x1b[B", 3); return;
        case 124: bridge_key_input((const uint8_t*)"\x1b[C", 3); return;
        case 123: bridge_key_input((const uint8_t*)"\x1b[D", 3); return;
        case 115: bridge_key_input((const uint8_t*)"\x1b[H", 3); return;
        case 119: bridge_key_input((const uint8_t*)"\x1b[F", 3); return;
        case 116: bridge_key_input((const uint8_t*)"\x1b[5~", 4); return;
        case 121: bridge_key_input((const uint8_t*)"\x1b[6~", 4); return;
        case 117: bridge_key_input((const uint8_t*)"\x1b[3~", 4); return;
        default: break;
    }

    NSString* chars = event.characters;
    if (chars && chars.length > 0) {
        const char* utf8 = [chars UTF8String];
        if (utf8) {
            bridge_key_input((const uint8_t*)utf8, (uint32_t)strlen(utf8));
        }
    }
}

@end

// === App Delegate ===
@interface STAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSWindow* window;
@property (nonatomic, strong) STTerminalView* termView;
@end

@implementation STAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;

    // Ensure PATH includes Homebrew locations — Finder/Launchpad/Raycast launch
    // with a minimal PATH that doesn't include /opt/homebrew/bin or /usr/local/bin
    const char* path = getenv("PATH");
    if (path) {
        char newpath[4096];
        snprintf(newpath, sizeof(newpath), "%s:/opt/homebrew/bin:/usr/local/bin", path);
        setenv("PATH", newpath, 1);
    } else {
        setenv("PATH", "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", 1);
    }

    // Ensure locale is set — without this, tmux uses VT100 line-drawing
    // escape sequences instead of UTF-8 box-drawing characters
    if (!getenv("LANG")) {
        setenv("LANG", "en_US.UTF-8", 1);
    }
    if (!getenv("LC_ALL")) {
        setenv("LC_ALL", "en_US.UTF-8", 1);
    }

    NSRect frame = NSMakeRect(100, 100, 1280, 820);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable |
                       NSWindowStyleMaskFullSizeContentView;
    self.window = [[NSWindow alloc] initWithContentRect:frame
                                              styleMask:style
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"MultiplexTerm";
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.backgroundColor = g_bg;
    self.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.minSize = NSMakeSize(600, 400);

    self.termView = [[STTerminalView alloc] initWithFrame:self.window.contentView.bounds];
    self.termView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.termView];

    uint8_t result = bridge_init();
    if (result != 0) {
        NSAlert* alert = [[NSAlert alloc] init];
        alert.messageText = @"MultiplexTerm";
        alert.informativeText = (result == 1)
            ? @"tmux is not installed or not in PATH."
            : @"Failed to initialize terminal.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        [NSApp terminate:nil];
        return;
    }

    [self.termView recalcTermSize];

    self.termView.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/60.0
                                                              target:self.termView
                                                            selector:@selector(tick:)
                                                            userInfo:nil
                                                             repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.termView.tickTimer forMode:NSRunLoopCommonModes];

    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.termView];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app {
    (void)app;
    return YES;
}

@end

// === Entry point ===
void platform_run(void) {
    @autoreleasepool {
        initTheme();
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        // Menu bar
        NSMenu* menuBar = [[NSMenu alloc] init];
        NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
        [menuBar addItem:appMenuItem];
        NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"MultiplexTerm"];
        [appMenu addItemWithTitle:@"Quit MultiplexTerm"
                           action:@selector(terminate:)
                    keyEquivalent:@"q"];
        [appMenuItem setSubmenu:appMenu];
        [NSApp setMainMenu:menuBar];

        STAppDelegate* delegate = [[STAppDelegate alloc] init];
        [NSApp setDelegate:delegate];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run];
    }
}
