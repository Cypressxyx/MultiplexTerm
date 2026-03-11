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

// === Layout constants ===
static const CGFloat kSidebarWidth    = 220.0;
static const CGFloat kSidebarPadH     = 16.0;
static const CGFloat kHeaderHeight    = 48.0;
static const CGFloat kSessionRowH     = 34.0;
static const CGFloat kNewBtnHeight    = 44.0;
static const CGFloat kAccentBarW      = 3.0;
static const CGFloat kTermPadLeft     = 4.0;
static const CGFloat kTitlebarInset   = 28.0; // space for traffic light buttons

// === Theme colors (Vercel dark) ===
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

static void initTheme(void) {
    g_bg         = hexColor(0x0A0A0A);
    g_sidebarBg  = hexColor(0x111111);
    g_border     = hexColor(0x2A2A2A);
    g_text       = hexColor(0xEDEDED);
    g_textDim    = hexColor(0x888888);
    g_textMuted  = hexColor(0x555555);
    g_selectedBg = hexColor(0x1A1A1A);
    g_hoverBg    = hexColor(0x161616);
    g_accent     = hexColor(0xFAFAFA);
    g_green      = hexColor(0x50E3C2);
    g_cursor     = hexColor(0xFAFAFA);
    g_defaultFg  = hexColor(0xEDEDED);
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
// Command palette
@property (nonatomic) BOOL paletteVisible;
@property (nonatomic) NSInteger paletteSelection;
@end

static const int kPaletteItemCount = 8;
static NSString* const kPaletteLabels[] = {
    @"Split Pane Right",
    @"Split Pane Down",
    @"New Window",
    @"Next Window",
    @"Previous Window",
    @"Next Pane",
    @"Close Pane",
    @"Toggle Zoom",
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
        self.closeArmedSession = -1;
        self.cursorBlink = YES;
        self.blinkCounter = 0;
        self.hasSelection = NO;
        self.isDragging = NO;
        self.paletteVisible = NO;
        self.paletteSelection = 0;
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
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    @autoreleasepool {
        // Full background
        [g_bg setFill];
        NSRectFill(self.bounds);

        // Terminal content
        [self drawTerminal];

        // Cursor
        if (bridge_get_cursor_visible() && self.cursorBlink) {
            [self drawCursor];
        }

        // Sidebar (drawn on top of terminal)
        if (bridge_is_sidebar_visible()) {
            [self drawSidebar];
        }

        // Command palette overlay
        if (self.paletteVisible) {
            [self drawPalette];
        }
    }
}

- (void)drawSidebar {
    CGFloat h = self.bounds.size.height;
    CGFloat sw = kSidebarWidth;

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
        };
        [name drawAtPoint:NSMakePoint(textX, textY) withAttributes:nameAttrs];

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
        if (y + kSessionRowH > h - kNewBtnHeight) break;
    }

    // Bottom: "+ New Session" button
    CGFloat btnY = h - kNewBtnHeight;

    // Top border
    [g_border setFill];
    NSRectFill(NSMakeRect(0, btnY, sw, 1));

    // Button text
    NSDictionary* btnAttrs = @{
        NSFontAttributeName: self.uiFont,
        NSForegroundColorAttributeName: g_textMuted,
    };
    NSString* btnText = @"+ New Session";
    CGSize btnSz = [btnText sizeWithAttributes:btnAttrs];
    CGFloat btnTextX = (sw - btnSz.width) / 2;
    CGFloat btnTextY = btnY + (kNewBtnHeight - btnSz.height) / 2;
    [btnText drawAtPoint:NSMakePoint(btnTextX, btnTextY) withAttributes:btnAttrs];
}

- (void)drawPalette {
    CGFloat w = self.bounds.size.width;
    CGFloat h = self.bounds.size.height;

    // Dim overlay
    [[NSColor colorWithWhite:0 alpha:0.5] setFill];
    NSRectFill(self.bounds);

    // Palette card
    CGFloat cardW = 320;
    CGFloat rowH = 38;
    CGFloat headerH = 44;
    CGFloat cardH = headerH + rowH * kPaletteItemCount + 8;
    CGFloat cardX = (w - cardW) / 2;
    CGFloat cardY = h * 0.2;

    NSBezierPath* cardPath = [NSBezierPath bezierPathWithRoundedRect:
        NSMakeRect(cardX, cardY, cardW, cardH) xRadius:12 yRadius:12];
    [hexColor(0x141414) setFill];
    [cardPath fill];

    // Card border
    [hexColor(0x2A2A2A) setStroke];
    cardPath.lineWidth = 1;
    [cardPath stroke];

    // Title
    NSDictionary* titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: g_text,
    };
    [@"Commands" drawAtPoint:NSMakePoint(cardX + 20, cardY + 14) withAttributes:titleAttrs];

    // Separator
    [hexColor(0x2A2A2A) setFill];
    NSRectFill(NSMakeRect(cardX, cardY + headerH, cardW, 1));

    // Items
    CGFloat itemY = cardY + headerH + 4;
    for (int i = 0; i < kPaletteItemCount; i++) {
        BOOL sel = (self.paletteSelection == i);

        if (sel) {
            NSBezierPath* rowBg = [NSBezierPath bezierPathWithRoundedRect:
                NSMakeRect(cardX + 6, itemY, cardW - 12, rowH) xRadius:6 yRadius:6];
            [hexColor(0x1E1E1E) setFill];
            [rowBg fill];
        }

        // Icon/hint on left
        NSDictionary* hintAttrs = @{
            NSFontAttributeName: [NSFont monospacedSystemFontOfSize:15 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: sel ? g_green : g_textMuted,
        };
        [kPaletteHints[i] drawAtPoint:NSMakePoint(cardX + 20, itemY + 9) withAttributes:hintAttrs];

        // Label
        NSDictionary* labelAttrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:13 weight:sel ? NSFontWeightMedium : NSFontWeightRegular],
            NSForegroundColorAttributeName: sel ? g_text : g_textDim,
        };
        [kPaletteLabels[i] drawAtPoint:NSMakePoint(cardX + 48, itemY + 10) withAttributes:labelAttrs];

        itemY += rowH;
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
        CGFloat cardW = 320;
        CGFloat rowH = 38;
        CGFloat headerH = 44;
        CGFloat cardH = headerH + rowH * kPaletteItemCount + 8;
        CGFloat cardX = (w - cardW) / 2;
        CGFloat cardY = h * 0.2;

        if (p.x >= cardX && p.x <= cardX + cardW &&
            p.y >= cardY + headerH && p.y <= cardY + cardH) {
            int idx = (int)((p.y - cardY - headerH - 4) / rowH);
            if (idx >= 0 && idx < kPaletteItemCount) {
                bridge_tmux_command((uint8_t)idx);
                self.paletteVisible = NO;
                [self setNeedsDisplay:YES];
                return;
            }
        }
        // Click outside dismisses
        self.paletteVisible = NO;
        [self setNeedsDisplay:YES];
        return;
    }

    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth) {
        CGFloat h = self.bounds.size.height;
        CGFloat btnY = h - kNewBtnHeight;

        // "+ New Session" button
        if (p.y >= btnY) {
            bridge_create_session();
            return;
        }

        // Session click
        if (p.y >= listTop) {
            uint16_t idx = (uint16_t)((p.y - listTop) / kSessionRowH);
            uint16_t count = bridge_get_session_count();
            if (idx < count) {
                // Close button hit (right 28px of row)
                if (p.x >= kSidebarWidth - 28) {
                    if (self.closeArmedSession == idx) {
                        // Second click — actually delete
                        self.closeArmedSession = -1;
                        bridge_kill_session(idx);
                    } else {
                        // First click — arm (turns red)
                        self.closeArmedSession = idx;
                        [self setNeedsDisplay:YES];
                    }
                    return;
                }

                // Double-click to rename
                if (event.clickCount == 2) {
                    [self promptRenameSession:idx];
                    return;
                }

                // Clicking elsewhere disarms the close button
                self.closeArmedSession = -1;

                bridge_select_session(idx);
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
        CGFloat btnY = self.bounds.size.height - kNewBtnHeight;
        if (p.y < btnY) {
            uint16_t idx = (uint16_t)((p.y - listTop) / kSessionRowH);
            uint16_t count = bridge_get_session_count();
            if (idx < count) {
                [self showContextMenuForSession:idx event:event];
                return;
            }
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



- (void)mouseMoved:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];

    // Palette hover
    if (self.paletteVisible) {
        CGFloat w = self.bounds.size.width;
        CGFloat h = self.bounds.size.height;
        CGFloat cardW = 320;
        CGFloat rowH = 38;
        CGFloat headerH = 44;
        CGFloat cardX = (w - cardW) / 2;
        CGFloat cardY = h * 0.2;
        CGFloat itemsTop = cardY + headerH + 4;

        if (p.x >= cardX && p.x <= cardX + cardW && p.y >= itemsTop) {
            int idx = (int)((p.y - itemsTop) / rowH);
            if (idx >= 0 && idx < kPaletteItemCount && idx != self.paletteSelection) {
                self.paletteSelection = idx;
                [self setNeedsDisplay:YES];
            }
        }
        [[NSCursor pointingHandCursor] set];
        return;
    }

    NSInteger old = self.hoveredSession;
    CGFloat listTop = kTitlebarInset + kHeaderHeight;

    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth && p.y >= listTop) {
        CGFloat btnY = self.bounds.size.height - kNewBtnHeight;
        if (p.y < btnY) {
            self.hoveredSession = (NSInteger)((p.y - listTop) / kSessionRowH);
            uint16_t count = bridge_get_session_count();
            if (self.hoveredSession >= count) self.hoveredSession = -1;
        } else {
            self.hoveredSession = -1;
        }
    } else {
        self.hoveredSession = -1;
    }

    if (old != self.hoveredSession) {
        [self setNeedsDisplay:YES];
    }

    // Cursor style
    if (bridge_is_sidebar_visible() && p.x < kSidebarWidth && p.y >= listTop) {
        [[NSCursor pointingHandCursor] set];
    } else {
        [[NSCursor IBeamCursor] set];
    }
}

- (void)scrollWheel:(NSEvent*)event {
    if (self.paletteVisible) return;
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
    // Command palette navigation
    if (self.paletteVisible) {
        switch (event.keyCode) {
            case 126: // Up
                self.paletteSelection = (self.paletteSelection - 1 + kPaletteItemCount) % kPaletteItemCount;
                [self setNeedsDisplay:YES];
                return;
            case 125: // Down
                self.paletteSelection = (self.paletteSelection + 1) % kPaletteItemCount;
                [self setNeedsDisplay:YES];
                return;
            case 36: // Enter
                bridge_tmux_command((uint8_t)self.paletteSelection);
                self.paletteVisible = NO;
                [self setNeedsDisplay:YES];
                return;
            case 53: // Escape
                self.paletteVisible = NO;
                [self setNeedsDisplay:YES];
                return;
            default:
                return; // swallow all other keys while palette is open
        }
    }

    if (event.modifierFlags & NSEventModifierFlagCommand) {
        NSString* chars = event.charactersIgnoringModifiers;
        // Cmd+K — toggle command palette
        if ([chars isEqualToString:@"k"]) {
            self.paletteVisible = !self.paletteVisible;
            self.paletteSelection = 0;
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
    self.window.backgroundColor = hexColor(0x0A0A0A);
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
