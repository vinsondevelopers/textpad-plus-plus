// Renders the Textpad++ application icon (original artwork, not the Notepad++ logo) into an
// .iconset folder for iconutil: a cream rounded square with a dark line drawing of a spiral
// notebook and a pen. Usage: make_icon <out.iconset> [preview.png]
#import <Cocoa/Cocoa.h>
#include <math.h>

static NSColor *rgb(int hex) {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0 blue:(hex & 0xFF) / 255.0 alpha:1];
}

// the glyph on a 24-unit grid, y pointing down (like an SVG icon); strokes 2 units wide
static NSBezierPath *glyph(void) {
    NSBezierPath *g = [NSBezierPath bezierPath];
    // notebook cover, open at the top right where the pen crosses it
    const CGFloat L = 5.5, T = 3, R = 19, B = 21, r = 2.5;
    [g moveToPoint:NSMakePoint(13.2, T)];
    [g lineToPoint:NSMakePoint(L + r, T)];
    [g appendBezierPathWithArcWithCenter:NSMakePoint(L + r, T + r) radius:r startAngle:270 endAngle:180 clockwise:YES];
    [g lineToPoint:NSMakePoint(L, B - r)];
    [g appendBezierPathWithArcWithCenter:NSMakePoint(L + r, B - r) radius:r startAngle:180 endAngle:90 clockwise:YES];
    [g lineToPoint:NSMakePoint(R - r, B)];
    [g appendBezierPathWithArcWithCenter:NSMakePoint(R - r, B - r) radius:r startAngle:90 endAngle:0 clockwise:YES];
    [g lineToPoint:NSMakePoint(R, 12.8)];
    // spiral binding: three open hooks through the left edge
    const CGFloat rings[] = {7.2, 12.0, 16.8};
    for (int i = 0; i < 3; ++i) {
        const CGFloat y = rings[i], rr = 1.4;
        [g moveToPoint:NSMakePoint(L + 1.3, y - rr)];
        [g lineToPoint:NSMakePoint(3.3, y - rr)];
        [g appendBezierPathWithArcWithCenter:NSMakePoint(3.3, y) radius:rr startAngle:270 endAngle:90 clockwise:YES];
        [g lineToPoint:NSMakePoint(L, y + rr)];
    }
    // pen: a slanted body with a rounded end and a pointed nib, nib at the lower left
    const CGFloat dx = M_SQRT1_2, dy = -M_SQRT1_2;      // along the pen, towards the upper right
    const CGFloat nx = M_SQRT1_2, ny = M_SQRT1_2;       // across the pen
    const NSPoint tip = NSMakePoint(10.9, 13.1);
    const CGFloat half = 1.55, nib = 2.4, len = 11.2;
    NSPoint b0 = NSMakePoint(tip.x + nib * dx + half * nx, tip.y + nib * dy + half * ny);
    NSPoint b1 = NSMakePoint(tip.x + nib * dx - half * nx, tip.y + nib * dy - half * ny);
    NSPoint e = NSMakePoint(tip.x + len * dx, tip.y + len * dy);
    [g moveToPoint:tip];
    [g lineToPoint:b0];
    [g lineToPoint:NSMakePoint(e.x + half * nx, e.y + half * ny)];
    [g appendBezierPathWithArcWithCenter:e radius:half startAngle:45 endAngle:225 clockwise:YES];
    [g lineToPoint:b1];
    [g closePath];
    [g moveToPoint:b0];                                  // where the nib meets the body
    [g lineToPoint:b1];
    return g;
}

static void render(NSString *path, int px) {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:px pixelsHigh:px bitsPerSample:8
                                                               samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
    const CGFloat s = px / 1024.0;
    // macOS icon grid: an 824-point rounded square inside the 1024 canvas, with a soft shadow
    NSRect body = NSMakeRect(100 * s, 100 * s, 824 * s, 824 * s);
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:body xRadius:185 * s yRadius:185 * s];
    [NSGraphicsContext saveGraphicsState];
    NSShadow *sh = [NSShadow new];
    sh.shadowBlurRadius = 28 * s; sh.shadowOffset = NSMakeSize(0, -12 * s);
    sh.shadowColor = [NSColor colorWithWhite:0 alpha:0.30];
    [sh set];
    [rgb(0xF6ECCF) setFill];
    [tile fill];
    [NSGraphicsContext restoreGraphicsState];
    // cream gradient, lighter at the top left
    NSGradient *grad = [[NSGradient alloc] initWithStartingColor:rgb(0xFDF8E8) endingColor:rgb(0xEFE0B8)];
    [grad drawInBezierPath:tile angle:-60];
    [[NSColor colorWithWhite:0 alpha:0.06] setStroke];
    tile.lineWidth = MAX(1.0, 3 * s);
    [tile stroke];
    // the glyph: 24 units mapped to 24 points each, centred
    NSAffineTransform *t = [NSAffineTransform transform];
    const CGFloat k = 24 * s;
    [t translateXBy:512 * s yBy:512 * s];
    [t scaleXBy:k yBy:-k];
    [t translateXBy:-10.9 yBy:-12];
    NSBezierPath *g = glyph();
    [g transformUsingAffineTransform:t];
    g.lineWidth = 1.4 * k * (px <= 32 ? 1.35 : 1.0);   // a little bolder at 16 and 32 pixels
    g.lineCapStyle = NSLineCapStyleRound;
    g.lineJoinStyle = NSLineJoinStyleRound;
    [rgb(0x1F1C18) setStroke];
    [g stroke];
    [NSGraphicsContext restoreGraphicsState];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [png writeToFile:path atomically:YES];
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc < 2) return 1;
        NSString *dir = @(argv[1]);
        int sizes[] = {16, 32, 128, 256, 512};
        for (int i = 0; i < 5; ++i) {
            int sz = sizes[i];
            render([dir stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d.png", sz, sz]], sz);
            render([dir stringByAppendingPathComponent:[NSString stringWithFormat:@"icon_%dx%d@2x.png", sz, sz]], sz * 2);
        }
        if (argc > 2) render(@(argv[2]), 1024);
    }
    return 0;
}
